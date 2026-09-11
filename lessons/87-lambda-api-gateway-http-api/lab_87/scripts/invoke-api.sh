#!/usr/bin/env bash
# Disable tracing before resolving credentials, even when called with bash -x.
set +x
set -euo pipefail
umask 077

if [[ $# -ne 4 ]]; then
  echo 'Usage: invoke-api.sh API_ENDPOINT AWS_REGION BODY_FILE OUTPUT_PREFIX' >&2
  echo 'Signs POST /quotes using current AWS CLI credentials; saves body, headers and status.' >&2
  exit 2
fi
api_endpoint="${1%/}"
api_region="$2"
body_file="$3"
output_prefix="$4"

for executable in aws curl jq; do
  command -v "$executable" >/dev/null || { echo "Missing command: $executable" >&2; exit 2; }
done
# Restrict signed requests to this lab's commercial execute-api endpoint.
if [[ ! "$api_endpoint" =~ ^https://[a-z0-9]+\.execute-api\.([a-z]{2}-[a-z]+-[0-9]+)\.amazonaws\.com$ ]] || [[ "${BASH_REMATCH[1]:-}" != "$api_region" ]]; then
  echo 'Use the Terraform api_endpoint output and its matching AWS Region.' >&2
  exit 2
fi
if [[ ! -r "$body_file" || ! -f "$body_file" || -z "$output_prefix" ]]; then
  echo 'BODY_FILE must be readable and OUTPUT_PREFIX must not be empty.' >&2
  exit 2
fi
mkdir -p "$(dirname "$output_prefix")"

# Resolve the active profile/SSO session through AWS CLI. Keep credentials in
# memory, out of files, output artifacts, and curl command-line arguments.
credentials_json="$(aws configure export-credentials --format process)"
if ! jq -e '
  (.AccessKeyId | type == "string" and test("^[A-Za-z0-9]+$")) and
  (.SecretAccessKey | type == "string" and test("^[A-Za-z0-9/+=]+$")) and
  ((.SessionToken // "") | type == "string" and test("^[A-Za-z0-9/+=]*$"))
' <<<"$credentials_json" >/dev/null; then
  echo 'AWS CLI returned an invalid credential structure.' >&2
  exit 2
fi
access_key_id="$(jq -r '.AccessKeyId' <<<"$credentials_json")"
secret_access_key="$(jq -r '.SecretAccessKey' <<<"$credentials_json")"
session_token="$(jq -r '.SessionToken // empty' <<<"$credentials_json")"
unset credentials_json

# A failed connection must not leave a previous successful response under the same
# output prefix. These artifacts contain responses only, never credentials.
: >"$output_prefix.body.json"
: >"$output_prefix.headers.txt"
curl_status=0
{
  printf 'user = "%s:%s"\n' "$access_key_id" "$secret_access_key"
  if [[ -n "$session_token" ]]; then
    printf 'header = "X-Amz-Security-Token: %s"\n' "$session_token"
  fi
} | curl -q --config - \
  --aws-sigv4 "aws:amz:$api_region:execute-api" \
  --proto '=https' --connect-timeout 5 --max-time 15 \
  --silent --show-error --fail-with-body \
  --request POST --header 'Content-Type: application/json' \
  --data-binary "@$body_file" \
  --dump-header "$output_prefix.headers.txt" \
  --output "$output_prefix.body.json" \
  --write-out '%{http_code}\n' \
  "$api_endpoint/quotes" >"$output_prefix.status.txt" || curl_status=$?

unset access_key_id secret_access_key session_token
printf 'HTTP=%s artifacts=%s.*\n' "$(cat "$output_prefix.status.txt")" "$output_prefix"
# HTTP 4xx/5xx remain nonzero while bodies are retained for diagnostics.
# No automatic POST retry: a timeout does not prove the operation failed.
exit "$curl_status"
