#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  invoke-sync.sh FUNCTION_NAME REGION EVENT_FILE METADATA_FILE RESPONSE_FILE
EOF
}

if [[ $# -ne 5 ]]; then
  usage >&2
  exit 2
fi

function_name=$1
region=$2
event_file=$3
metadata_file=$4
response_file=$5

[[ -f "$event_file" ]] || {
  printf 'Event file not found: %s\n' "$event_file" >&2
  exit 2
}

mkdir -p "$(dirname "$metadata_file")" "$(dirname "$response_file")"

# AWS CLI writes invocation metadata to stdout and the decoded handler payload
# to the file passed as the final positional argument.
aws lambda invoke \
  --function-name "$function_name" \
  --region "$region" \
  --cli-binary-format raw-in-base64-out \
  --payload "fileb://${event_file}" \
  "$response_file" >"$metadata_file"

printf 'metadata=%s\nresponse=%s\n' "$metadata_file" "$response_file"
