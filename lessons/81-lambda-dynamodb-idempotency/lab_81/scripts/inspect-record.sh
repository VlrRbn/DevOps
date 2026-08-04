#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  inspect-record.sh TABLE_NAME REGION IDEMPOTENCY_KEY OUTPUT_FILE
EOF
}

if [[ $# -ne 4 ]]; then
  usage >&2
  exit 2
fi

table_name=$1
region=$2
idempotency_key=$3
output_file=$4

mkdir -p "$(dirname "$output_file")"

# A strong read avoids showing an older state immediately after Lambda writes
# the claim or completion record.
aws dynamodb get-item \
  --table-name "$table_name" \
  --region "$region" \
  --consistent-read \
  --key "$(jq -cn --arg key "$idempotency_key" \
    '{idempotency_key: {S: $key}}')" \
  --output json >"$output_file"

jq . "$output_file"
