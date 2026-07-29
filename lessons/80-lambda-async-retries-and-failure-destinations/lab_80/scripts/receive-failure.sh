#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  receive-failure.sh QUEUE_URL REGION OUTPUT_FILE EVENT_ID [MAX_ATTEMPTS]
USAGE
}

if [[ $# -lt 4 || $# -gt 5 ]]; then
  usage
  exit 2
fi

queue_url="$1"
aws_region="$2"
output_file="$3"
expected_event_id="$4"
max_attempts="${5:-18}"

for required_command in aws jq; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$required_command" >&2
    exit 1
  }
done

[[ "$max_attempts" =~ ^[1-9][0-9]*$ ]] || {
  printf 'MAX_ATTEMPTS must be a positive integer\n' >&2
  exit 2
}

[[ -n "$expected_event_id" ]] || {
  printf 'EVENT_ID must not be empty\n' >&2
  exit 2
}

batch_file="$(mktemp)"
trap 'rm -f "$batch_file"' EXIT

for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  # Read a batch because earlier drills may have left other failure records in
  # the queue. Visibility timeout 0 keeps every message available for inspection.
  aws sqs receive-message \
    --region "$aws_region" \
    --queue-url "$queue_url" \
    --max-number-of-messages 10 \
    --wait-time-seconds 10 \
    --visibility-timeout 0 \
    --attribute-names All \
    --message-attribute-names All \
    --output json >"$batch_file"

  # SQS Body is a JSON string containing Lambda's invocation record. Preserve
  # the familiar .Messages[0] shape while selecting the requested event only.
  if jq -e --arg event_id "$expected_event_id" '
    [
      .Messages[]?
      | select((.Body | fromjson? | .requestPayload.event_id) == $event_id)
    ]
    | if length > 0 then {Messages: [.[0]]} else empty end
  ' "$batch_file" >"$output_file"; then
    printf 'failure record received: event_id=%s file=%s\n' \
      "$expected_event_id" "$output_file"
    exit 0
  fi

  printf 'no failure record for event_id=%s yet (attempt %s/%s)\n' \
    "$expected_event_id" "$attempt" "$max_attempts" >&2
done

printf 'no failure record for event_id=%s after %s attempts\n' \
  "$expected_event_id" "$max_attempts" >&2
exit 1
