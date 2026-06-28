#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  list-state-versions.sh <bucket> <state-key>

Lists S3 object versions for a Terraform state key.
It does not restore, copy, or delete state.
USAGE
}

BUCKET="${1:-}"
STATE_KEY="${2:-}"

if [[ -z "$BUCKET" || -z "$STATE_KEY" ]]; then
  usage
  exit 64
fi

aws s3api list-object-versions \
  --bucket "$BUCKET" \
  --prefix "$STATE_KEY" \
  --query 'Versions[].{Key:Key,VersionId:VersionId,IsLatest:IsLatest,LastModified:LastModified,Size:Size}' \
  --output table \
  --no-cli-pager
