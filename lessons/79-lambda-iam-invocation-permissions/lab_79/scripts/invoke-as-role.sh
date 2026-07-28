#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  invoke-as-role.sh ROLE_ARN FUNCTION_NAME AWS_REGION PAYLOAD_FILE RESPONSE_FILE METADATA_FILE

The current AWS identity assumes ROLE_ARN. Temporary STS credentials are scoped
to this process and are not written to disk.
USAGE
}

if [[ $# -ne 6 ]]; then
  usage >&2
  exit 64
fi

role_arn="$1"
function_name="$2"
aws_region="$3"
payload_file="$4"
response_file="$5"
metadata_file="$6"

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

session_json="$(
  aws sts assume-role \
    --role-arn "$role_arn" \
    --role-session-name "lesson79-invoke-$(date +%s)" \
    --duration-seconds 900 \
    --output json
)"

access_key_id="$(jq -er '.Credentials.AccessKeyId' <<<"$session_json")"
secret_access_key="$(jq -er '.Credentials.SecretAccessKey' <<<"$session_json")"
session_token="$(jq -er '.Credentials.SessionToken' <<<"$session_json")"

# Disable errexit briefly so an expected AccessDenied can be inspected by the
# caller instead of terminating before the script reports the AWS CLI status.
set +e
AWS_ACCESS_KEY_ID="$access_key_id" \
AWS_SECRET_ACCESS_KEY="$secret_access_key" \
AWS_SESSION_TOKEN="$session_token" \
AWS_REGION="$aws_region" \
aws lambda invoke \
  --function-name "$function_name" \
  --cli-binary-format raw-in-base64-out \
  --payload "fileb://${payload_file}" \
  "$response_file" \
  >"$metadata_file"
aws_cli_exit_code=$?
set -e

printf 'aws_cli_exit_code=%s\n' "$aws_cli_exit_code"

if [[ $aws_cli_exit_code -ne 0 ]]; then
  exit "$aws_cli_exit_code"
fi

jq . "$metadata_file"
jq . "$response_file"

if jq -e 'has("FunctionError")' "$metadata_file" >/dev/null; then
  printf 'Lambda API accepted the request, but the handler failed\n' >&2
  exit 2
fi
