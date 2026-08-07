#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: receive-messages.sh QUEUE_URL AWS_REGION OUTPUT_FILE

Receives up to ten messages for inspection without deleting them. Visibility is
set to zero so the command does not hide evidence from the event source mapping.
USAGE
}

if [[ $# -ne 3 ]]; then
  usage >&2
  exit 2
fi

queue_url="$1"
aws_region="$2"
output_file="$3"

mkdir -p "$(dirname "$output_file")"

aws sqs receive-message \
  --queue-url "$queue_url" \
  --region "$aws_region" \
  --max-number-of-messages 10 \
  --wait-time-seconds 2 \
  --visibility-timeout 0 \
  --attribute-names All \
  --message-attribute-names All \
  --output json >"$output_file"

jq . "$output_file"
