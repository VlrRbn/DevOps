#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: send-dedup-pair.sh QUEUE_URL AWS_REGION GROUP_ID DEDUPLICATION_ID OUTPUT_FILE

Sends two different FIFO message bodies with the same explicit deduplication ID.
SQS acknowledges both requests but should deliver only the first message during
the five-minute deduplication interval.
USAGE
}

if [[ $# -ne 5 ]]; then
  usage >&2
  exit 2
fi

queue_url="$1"
aws_region="$2"
group_id="$3"
deduplication_id="$4"
output_file="$5"

if ! [[ "$group_id" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
  printf 'GROUP_ID must contain 1-64 letters, numbers, underscores, or dashes.\n' >&2
  exit 2
fi

if ! [[ "$deduplication_id" =~ ^[A-Za-z0-9_-]{1,96}$ ]]; then
  printf 'DEDUPLICATION_ID must contain 1-96 letters, numbers, underscores, or dashes.\n' >&2
  exit 2
fi

mkdir -p "$(dirname "$output_file")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

for variant in first second; do
  body="$(jq -cn \
    --arg task_id "dedup-${variant}" \
    --arg variant "$variant" \
    '{
      task_id: $task_id,
      sequence: (if $variant == "first" then 1 else 2 end),
      work_seconds: 0,
      should_fail: false
    }')"

  aws sqs send-message \
    --queue-url "$queue_url" \
    --region "$aws_region" \
    --message-group-id "$group_id" \
    --message-deduplication-id "$deduplication_id" \
    --message-body "$body" \
    --output json >"$tmp_dir/${variant}.json"
done

jq -n \
  --arg group_id "$group_id" \
  --arg deduplication_id "$deduplication_id" \
  --slurpfile first "$tmp_dir/first.json" \
  --slurpfile second "$tmp_dir/second.json" \
  '{
    group_id: $group_id,
    deduplication_id: $deduplication_id,
    requests: [
      {variant: "first", response: $first[0]},
      {variant: "second", response: $second[0]}
    ]
  }' >"$output_file"

printf 'group_id=%s deduplication_id=%s successful_send_api_calls=2 output=%s\n' \
  "$group_id" "$deduplication_id" "$output_file"
