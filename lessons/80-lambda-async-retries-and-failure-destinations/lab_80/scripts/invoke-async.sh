#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  invoke-async.sh FUNCTION_NAME AWS_REGION PAYLOAD_FILE METADATA_FILE
USAGE
}

if [[ $# -ne 4 ]]; then
  usage >&2
  exit 64
fi

function_name="$1"
aws_region="$2"
payload_file="$3"
metadata_file="$4"

for required_command in aws jq; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$required_command" >&2
    exit 1
  }
done

if [[ ! -f "$payload_file" ]]; then
  printf 'payload file not found: %s\n' "$payload_file" >&2
  exit 1
fi

# InvocationType=Event asks Lambda to enqueue the event and return immediately.
# The metadata proves acceptance by the Lambda API, not handler success.
aws lambda invoke \
  --region "$aws_region" \
  --function-name "$function_name" \
  --invocation-type Event \
  --cli-binary-format raw-in-base64-out \
  --payload "fileb://${payload_file}" \
  /dev/null >"$metadata_file"

status_code="$(jq -r '.StatusCode // 0' "$metadata_file")"
if [[ "$status_code" != "202" ]]; then
  printf 'expected asynchronous StatusCode 202, got %s\n' "$status_code" >&2
  exit 1
fi

printf 'event accepted: function=%s status_code=%s metadata=%s\n' \
  "$function_name" "$status_code" "$metadata_file"
