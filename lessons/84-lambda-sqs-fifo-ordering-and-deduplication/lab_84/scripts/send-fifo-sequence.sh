#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: send-fifo-sequence.sh QUEUE_URL AWS_REGION GROUP_ID COUNT WORK_SECONDS FAIL_AT OUTPUT_FILE

Sends 1-100 ordered FIFO work items with explicit message group and deduplication IDs.
FAIL_AT is 0 for no planned failure or a sequence number between 1 and COUNT.
USAGE
}

if [[ $# -ne 7 ]]; then
  usage >&2
  exit 2
fi

queue_url="$1"
aws_region="$2"
group_id="$3"
count="$4"
work_seconds="$5"
fail_at="$6"
output_file="$7"

if ! [[ "$group_id" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
  printf 'GROUP_ID must contain 1-64 letters, numbers, underscores, or dashes.\n' >&2
  exit 2
fi

if ! [[ "$count" =~ ^[0-9]+$ ]] || ((count < 1 || count > 100)); then
  printf 'COUNT must be an integer between 1 and 100.\n' >&2
  exit 2
fi

if ! jq -en --arg value "$work_seconds" \
  '($value | tonumber?) as $n | $n != null and $n >= 0 and $n <= 3' >/dev/null; then
  printf 'WORK_SECONDS must be a number between 0 and 3.\n' >&2
  exit 2
fi

if ! [[ "$fail_at" =~ ^[0-9]+$ ]] || ((fail_at > count)); then
  printf 'FAIL_AT must be 0 or an integer between 1 and COUNT.\n' >&2
  exit 2
fi

mkdir -p "$(dirname "$output_file")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_id="$(date -u +%Y%m%dT%H%M%S)-$$"
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
    --arg group_id "$group_id" \
    --arg run_id "$run_id" \
    --argjson start "$sent" \
    --argjson amount "$batch_count" \
    --argjson work_seconds "$work_seconds" \
    --argjson fail_at "$fail_at" \
    '[range($start; $start + $amount) as $i |
      (($i + 1) | tostring) as $sequence |
      {
        Id: ("entry-" + $sequence),
        MessageGroupId: $group_id,
        MessageDeduplicationId: ($run_id + "-" + $group_id + "-" + $sequence),
        MessageBody: ({
          task_id: ($group_id + "-" + $run_id + "-task-" + $sequence),
          sequence: ($i + 1),
          work_seconds: $work_seconds,
          should_fail: (($i + 1) == $fail_at)
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

jq -s \
  --arg run_id "$run_id" \
  --arg group_id "$group_id" \
  --argjson requested "$count" \
  '{
    run_id: $run_id,
    group_id: $group_id,
    requested: $requested,
    responses: .
  }' "${response_files[@]}" >"$output_file"

failed_count="$(jq '[.responses[].Failed[]?] | length' "$output_file")"
successful_count="$(jq '[.responses[].Successful[]?] | length' "$output_file")"

printf 'run_id=%s group_id=%s requested=%d successful=%s failed=%s output=%s\n' \
  "$run_id" "$group_id" "$count" "$successful_count" "$failed_count" "$output_file"

if ((failed_count > 0)); then
  jq '[.responses[].Failed[]?]' "$output_file" >&2
  exit 1
fi
