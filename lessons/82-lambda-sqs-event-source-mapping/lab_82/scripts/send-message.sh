#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: send-message.sh QUEUE_URL AWS_REGION BODY_FILE OUTPUT_FILE

Sends one JSON file as an SQS message body and saves SendMessage metadata.
USAGE
}

if [[ $# -ne 4 ]]; then
  usage >&2
  exit 2
fi

queue_url="$1"
aws_region="$2"
body_file="$3"
output_file="$4"

if [[ ! -f "$body_file" ]]; then
  printf 'Body file not found: %s\n' "$body_file" >&2
  exit 2
fi

jq -e 'type == "object"' "$body_file" >/dev/null
mkdir -p "$(dirname "$output_file")"

aws sqs send-message \
  --queue-url "$queue_url" \
  --region "$aws_region" \
  --message-body "file://${body_file}" \
  --output json >"$output_file"

jq . "$output_file"
