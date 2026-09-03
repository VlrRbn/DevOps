#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: publish-event.sh TOPIC_ARN AWS_REGION EVENT_ID EVENT_TYPE ORDER_ID AMOUNT FAIL_CONSUMER OUTPUT_FILE

Publishes one JSON business event with an SNS event_type message attribute.
Use '-' for FAIL_CONSUMER unless the billing or audit branch should fail.
USAGE
}

if [[ $# -ne 8 ]]; then
  usage >&2
  exit 2
fi

topic_arn="$1"
aws_region="$2"
event_id="$3"
event_type="$4"
order_id="$5"
amount="$6"
fail_consumer="$7"
output_file="$8"

if ! [[ "$event_id" =~ ^[A-Za-z0-9._-]{1,96}$ ]]; then
  printf 'EVENT_ID must contain 1-96 letters, numbers, dots, underscores, or dashes.\n' >&2
  exit 2
fi

if ! [[ "$event_type" =~ ^[a-z][a-z0-9.-]{2,63}$ ]]; then
  printf 'EVENT_TYPE must be a lowercase dotted event name.\n' >&2
  exit 2
fi

if ! [[ "$order_id" =~ ^[A-Za-z0-9._-]{1,96}$ ]]; then
  printf 'ORDER_ID must contain 1-96 letters, numbers, dots, underscores, or dashes.\n' >&2
  exit 2
fi

if ! jq -en --arg value "$amount" \
  '($value | tonumber?) as $number | $number != null and $number >= 0' >/dev/null; then
  printf 'AMOUNT must be a non-negative number.\n' >&2
  exit 2
fi

if [[ "$fail_consumer" != "-" && "$fail_consumer" != "audit" && "$fail_consumer" != "billing" ]]; then
  printf 'FAIL_CONSUMER must be -, audit, or billing.\n' >&2
  exit 2
fi

mkdir -p "$(dirname "$output_file")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail_consumer_json="null"
if [[ "$fail_consumer" != "-" ]]; then
  fail_consumer_json="$(jq -Rn --arg value "$fail_consumer" '$value')"
fi

jq -cn \
  --arg event_id "$event_id" \
  --arg event_type "$event_type" \
  --arg order_id "$order_id" \
  --argjson amount "$amount" \
  --argjson fail_consumer "$fail_consumer_json" \
  '{
    event_id: $event_id,
    event_type: $event_type,
    order_id: $order_id,
    amount: $amount,
    fail_consumer: $fail_consumer
  }' >"$tmp_dir/message.json"

jq -n \
  --arg event_type "$event_type" \
  '{
    event_type: {
      DataType: "String",
      StringValue: $event_type
    }
  }' >"$tmp_dir/attributes.json"

aws sns publish \
  --topic-arn "$topic_arn" \
  --region "$aws_region" \
  --message "file://$tmp_dir/message.json" \
  --message-attributes "file://$tmp_dir/attributes.json" \
  --output json >"$tmp_dir/response.json"

jq -n \
  --arg topic_arn "$topic_arn" \
  --slurpfile message "$tmp_dir/message.json" \
  --slurpfile attributes "$tmp_dir/attributes.json" \
  --slurpfile response "$tmp_dir/response.json" \
  '{
    topic_arn: $topic_arn,
    message: $message[0],
    message_attributes: $attributes[0],
    publish_response: $response[0]
  }' >"$output_file"

printf 'event_id=%s event_type=%s sns_message_id=%s output=%s\n' \
  "$event_id" "$event_type" "$(jq -r '.publish_response.MessageId' "$output_file")" "$output_file"
