#!/usr/bin/env bash
set -Eeuo pipefail

# Generate a promotion evidence JSON document.
#
# The risk classifier validates this JSON for stage/prod managed changes.
# This helper avoids hand-writing fields incorrectly during drills.
# It prints to stdout so callers can redirect it to an evidence file.

usage() {
  cat >&2 <<'USAGE'
Usage:
  promotion-evidence-template.sh <release-id> <source-env> <commit-sha> <source-workflow-run-url> [status]

Examples:
  promotion-evidence-template.sh l76-demo dev "$(git rev-parse HEAD)" "https://github.com/OWNER/REPO/actions/runs/123" > /tmp/promotion-evidence-stage.json
  promotion-evidence-template.sh l76-demo stage "$(git rev-parse HEAD)" "https://github.com/OWNER/REPO/actions/runs/456" > /tmp/promotion-evidence-prod.json
USAGE
}

RELEASE_ID="${1:-}"
SOURCE_ENV="${2:-}"
COMMIT_SHA="${3:-}"
SOURCE_WORKFLOW_RUN_URL="${4:-}"
STATUS="${5:-passed}"

if [[ -z "$RELEASE_ID" || -z "$SOURCE_ENV" || -z "$COMMIT_SHA" || -z "$SOURCE_WORKFLOW_RUN_URL" ]]; then
  usage
  exit 64
fi

case "$SOURCE_ENV" in
  dev|stage|prod) ;;
  *) echo "source-env must be one of: dev, stage, prod" >&2; exit 64 ;;
esac

if [[ ! "$COMMIT_SHA" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "commit-sha must look like a Git SHA" >&2
  exit 64
fi

if [[ ! "$SOURCE_WORKFLOW_RUN_URL" =~ ^https://github\.com/.+/actions/runs/[0-9]+(/.*)?$ ]]; then
  echo "source-workflow-run-url must look like a GitHub Actions run URL" >&2
  exit 64
fi

if [[ "$STATUS" != "passed" ]]; then
  echo "warning: status is not 'passed'; risk-classifier.sh will block this evidence" >&2
fi

jq -n \
  --arg release_id "$RELEASE_ID" \
  --arg source_env "$SOURCE_ENV" \
  --arg status "$STATUS" \
  --arg commit_sha "$COMMIT_SHA" \
  --arg source_workflow_run_url "$SOURCE_WORKFLOW_RUN_URL" \
  --arg generated_at_utc "$(date -u +%FT%TZ)" \
  '{
    release_id: $release_id,
    source_env: $source_env,
    status: $status,
    commit_sha: $commit_sha,
    source_workflow_run_url: $source_workflow_run_url,
    generated_at_utc: $generated_at_utc
  }'
