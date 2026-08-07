#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: inspect-queue.sh QUEUE_URL AWS_REGION OUTPUT_FILE

Saves queue depth, in-flight count, visibility timeout, and redrive attributes.
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

aws sqs get-queue-attributes \
  --queue-url "$queue_url" \
  --region "$aws_region" \
  --attribute-names \
    ApproximateNumberOfMessages \
    ApproximateNumberOfMessagesNotVisible \
    ApproximateNumberOfMessagesDelayed \
    VisibilityTimeout \
    RedrivePolicy \
  --output json >"$output_file"

jq . "$output_file"
