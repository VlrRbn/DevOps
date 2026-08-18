#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: sample-backlog.sh QUEUE_URL AWS_REGION INTERVAL_SECONDS SAMPLES OUTPUT_FILE

Samples approximate SQS visible, in-flight, and delayed message counts without
receiving or changing the visibility of any message.
USAGE
}

if [[ $# -ne 5 ]]; then
  usage >&2
  exit 2
fi

queue_url="$1"
aws_region="$2"
interval_seconds="$3"
samples="$4"
output_file="$5"

if ! [[ "$interval_seconds" =~ ^[0-9]+$ ]] || ((interval_seconds < 1 || interval_seconds > 60)); then
  printf 'INTERVAL_SECONDS must be an integer between 1 and 60.\n' >&2
  exit 2
fi

if ! [[ "$samples" =~ ^[0-9]+$ ]] || ((samples < 1 || samples > 120)); then
  printf 'SAMPLES must be an integer between 1 and 120.\n' >&2
  exit 2
fi

mkdir -p "$(dirname "$output_file")"
printf 'timestamp\tvisible\tin_flight\tdelayed\n' | tee "$output_file"

for ((sample = 1; sample <= samples; sample++)); do
  attributes="$(aws sqs get-queue-attributes \
    --queue-url "$queue_url" \
    --region "$aws_region" \
    --attribute-names \
      ApproximateNumberOfMessages \
      ApproximateNumberOfMessagesNotVisible \
      ApproximateNumberOfMessagesDelayed \
    --output json)"

  jq -r \
    '[(now | strftime("%Y-%m-%dT%H:%M:%SZ")),
      (.Attributes.ApproximateNumberOfMessages // "0"),
      (.Attributes.ApproximateNumberOfMessagesNotVisible // "0"),
      (.Attributes.ApproximateNumberOfMessagesDelayed // "0")]
     | @tsv' <<<"$attributes" | tee -a "$output_file"

  if ((sample < samples)); then
    sleep "$interval_seconds"
  fi
done

printf 'samples=%d output=%s\n' "$samples" "$output_file"
