#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: put-event.sh EVENT_BUS_NAME AWS_REGION EVENT_SOURCE EVENT_ID EVENT_KIND ORDER_ID AMOUNT FAIL_CONSUMER OUTPUT_FILE

Publishes one custom order event to EventBridge.
EVENT_KIND must be order.created or order.refunded.
Use '-' for FAIL_CONSUMER unless the audit or high_value branch should fail.
USAGE
}

if [[ $# -ne 9 ]]; then
  usage >&2
  exit 2
fi

event_bus_name="$1"
aws_region="$2"
event_source="$3"
event_id="$4"
event_kind="$5"
order_id="$6"
amount="$7"
fail_consumer="$8"
output_file="$9"

if ! [[ "$event_bus_name" =~ ^[A-Za-z0-9._-]{1,256}$ ]]; then
  printf 'EVENT_BUS_NAME contains unsupported characters.\n' >&2
  exit 2
fi

if ! [[ "$event_source" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{2,255}$ ]]; then
  printf 'EVENT_SOURCE contains unsupported characters.\n' >&2
  exit 2
fi

if ! [[ "$event_id" =~ ^[A-Za-z0-9._-]{1,96}$ ]]; then
  printf 'EVENT_ID must contain 1-96 letters, numbers, dots, underscores, or dashes.\n' >&2
  exit 2
fi

if ! [[ "$order_id" =~ ^[A-Za-z0-9._-]{1,96}$ ]]; then
  printf 'ORDER_ID must contain 1-96 letters, numbers, dots, underscores, or dashes.\n' >&2
  exit 2
fi

case "$event_kind" in
  order.created)
    detail_type="Order Created"
    ;;
  order.refunded)
    detail_type="Order Refunded"
    ;;
  *)
    printf 'EVENT_KIND must be order.created or order.refunded.\n' >&2
    exit 2
    ;;
esac

if ! jq -en --arg value "$amount" \
  '($value | tonumber?) as $number | $number != null and $number >= 0' >/dev/null; then
  printf 'AMOUNT must be a non-negative number.\n' >&2
  exit 2
fi

if [[ "$fail_consumer" != "-" && "$fail_consumer" != "audit" && "$fail_consumer" != "high_value" ]]; then
  printf 'FAIL_CONSUMER must be -, audit, or high_value.\n' >&2
  exit 2
fi

mkdir -p "$(dirname "$output_file")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# PutEvents can report success for a missing custom bus. Resolve the bus first
# so a typo cannot look like a successfully routed event.
aws events describe-event-bus \
  --name "$event_bus_name" \
  --region "$aws_region" \
  --output json >"$tmp_dir/event-bus.json"

fail_consumer_json="null"
if [[ "$fail_consumer" != "-" ]]; then
  fail_consumer_json="$(jq -Rn --arg value "$fail_consumer" '$value')"
fi

jq -cn \
  --arg event_id "$event_id" \
  --arg order_id "$order_id" \
  --argjson amount "$amount" \
  --argjson fail_consumer "$fail_consumer_json" \
  '{
    event_id: $event_id,
    order_id: $order_id,
    amount: $amount,
    fail_consumer: $fail_consumer
  }' >"$tmp_dir/detail.json"

# Detail is a JSON-encoded string inside each PutEvents request entry.
jq -n \
  --arg event_bus_name "$event_bus_name" \
  --arg event_source "$event_source" \
  --arg detail_type "$detail_type" \
  --slurpfile detail "$tmp_dir/detail.json" \
  '[{
    EventBusName: $event_bus_name,
    Source: $event_source,
    DetailType: $detail_type,
    Detail: ($detail[0] | tojson)
  }]' >"$tmp_dir/entries.json"

aws events put-events \
  --entries "file://$tmp_dir/entries.json" \
  --region "$aws_region" \
  --output json >"$tmp_dir/response.json"

jq -n \
  --arg event_bus_name "$event_bus_name" \
  --arg event_source "$event_source" \
  --arg event_kind "$event_kind" \
  --slurpfile detail "$tmp_dir/detail.json" \
  --slurpfile response "$tmp_dir/response.json" \
  '{
    event_bus_name: $event_bus_name,
    event_source: $event_source,
    event_kind: $event_kind,
    detail: $detail[0],
    put_events_response: $response[0]
  }' >"$output_file"

# AWS CLI may exit zero while one or more PutEvents entries failed.
failed_entry_count="$(jq -r '.put_events_response.FailedEntryCount' "$output_file")"
if [[ "$failed_entry_count" != "0" ]]; then
  jq '.put_events_response' "$output_file" >&2
  printf 'PutEvents rejected %s entries; evidence=%s\n' \
    "$failed_entry_count" "$output_file" >&2
  exit 1
fi

printf 'event_id=%s event_kind=%s eventbridge_event_id=%s output=%s\n' \
  "$event_id" \
  "$event_kind" \
  "$(jq -r '.put_events_response.Entries[0].EventId' "$output_file")" \
  "$output_file"
