#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: send-burst.sh QUEUE_URL AWS_REGION COUNT WORK_SECONDS OUTPUT_FILE

Sends 1-100 deterministic work items in SQS batches of up to ten and saves all
SendMessageBatch responses as one JSON array.
USAGE
}

if [[ $# -ne 5 ]]; then
  usage >&2
  exit 2
fi

queue_url="$1"
aws_region="$2"
count="$3"
work_seconds="$4"
output_file="$5"

if ! [[ "$count" =~ ^[0-9]+$ ]] || ((count < 1 || count > 100)); then
  printf 'COUNT must be an integer between 1 and 100.\n' >&2
  exit 2
fi

if ! jq -en --arg value "$work_seconds" \
  '($value | tonumber?) as $n | $n != null and $n >= 0 and $n <= 10' >/dev/null; then
  printf 'WORK_SECONDS must be a number between 0 and 10.\n' >&2
  exit 2
fi

mkdir -p "$(dirname "$output_file")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

response_files=()
sent=0
batch_number=0

while ((sent < count)); do
  remaining=$((count - sent))
  batch_count=10
  if ((remaining < batch_count)); then
    batch_count="$remaining"
  fi

  entries_file="$tmp_dir/entries-${batch_number}.json"
  response_file="$tmp_dir/response-${batch_number}.json"

  jq -n \
    --argjson start "$sent" \
    --argjson amount "$batch_count" \
    --argjson work_seconds "$work_seconds" \
    '[range($start; $start + $amount) as $i |
      {
        Id: ("entry-" + (($i + 1) | tostring)),
        MessageBody: ({
          task_id: ("burst-task-" + (($i + 1) | tostring)),
          work_seconds: $work_seconds
        } | tojson)
      }
    ]' >"$entries_file"

  aws sqs send-message-batch \
    --queue-url "$queue_url" \
    --region "$aws_region" \
    --entries "file://${entries_file}" \
    --output json >"$response_file"

  response_files+=("$response_file")
  sent=$((sent + batch_count))
  batch_number=$((batch_number + 1))
done

jq -s '.' "${response_files[@]}" >"$output_file"

failed_count="$(jq '[.[].Failed[]?] | length' "$output_file")"
successful_count="$(jq '[.[].Successful[]?] | length' "$output_file")"

printf 'requested=%d successful=%s failed=%s output=%s\n' \
  "$count" "$successful_count" "$failed_count" "$output_file"

if ((failed_count > 0)); then
  jq '[.[].Failed[]?]' "$output_file" >&2
  exit 1
fi
