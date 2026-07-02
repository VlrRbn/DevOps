#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
IFS=$'\n\t'
export AWS_PAGER=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  cloudtrail-audit-snapshot.sh [options]

CloudTrail evidence collector for lesson 77.
It does not create, update, delete, apply, destroy, or restore AWS resources.

Options:
  --region REGION            AWS region for CloudTrail lookup. Default: AWS_REGION or eu-west-1.
  --out-dir DIR              Output directory. Default: evidence/cloudtrail-audit_<timestamp>.
  --max-results N            Max CloudTrail events per lookup. Default: 20.
  --start-time TIME          Optional CloudTrail lookup start time, for example 2026-07-01T10:00:00Z.
  --end-time TIME            Optional CloudTrail lookup end time, for example 2026-07-01T11:00:00Z.
  --state-bucket NAME        Optional Terraform state bucket name for audit notes.
  --state-prefix PREFIX      Optional Terraform state prefix, for example lab76/.
  --release-id ID            Optional release/change id.
  --workflow-url URL         Optional GitHub workflow run URL.
  --trail-name NAME          Optional CloudTrail trail name for event selector evidence.
  -h, --help                 Show help.

Examples:
  cloudtrail-audit-snapshot.sh --region eu-west-1 --state-bucket my-tfstate --state-prefix lab76/
USAGE
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LESSON_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REGION="${AWS_REGION:-eu-west-1}"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
OUT_DIR="${OUT_DIR:-${LESSON_DIR}/evidence/cloudtrail-audit_${STAMP}}"
MAX_RESULTS="20"
START_TIME=""
END_TIME=""
STATE_BUCKET=""
STATE_PREFIX=""
RELEASE_ID="manual"
WORKFLOW_URL="n/a"
TRAIL_NAME=""

require_value() {
  local option="$1"
  local value="${2:-}"

  if [[ -z "$value" || "$value" == --* ]]; then
    echo "${option} requires a value" >&2
    exit 64
  fi

  printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$(require_value "$1" "${2:-}")"; shift 2 ;;
    --out-dir)
      OUT_DIR="$(require_value "$1" "${2:-}")"; shift 2 ;;
    --max-results)
      MAX_RESULTS="$(require_value "$1" "${2:-}")"; shift 2 ;;
    --start-time)
      START_TIME="$(require_value "$1" "${2:-}")"; shift 2 ;;
    --end-time)
      END_TIME="$(require_value "$1" "${2:-}")"; shift 2 ;;
    --state-bucket)
      STATE_BUCKET="$(require_value "$1" "${2:-}")"; shift 2 ;;
    --state-prefix)
      STATE_PREFIX="$(require_value "$1" "${2:-}")"; shift 2 ;;
    --release-id)
      RELEASE_ID="$(require_value "$1" "${2:-}")"; shift 2 ;;
    --workflow-url)
      WORKFLOW_URL="$(require_value "$1" "${2:-}")"; shift 2 ;;
    --trail-name)
      TRAIL_NAME="$(require_value "$1" "${2:-}")"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 64 ;;
  esac
done

if [[ -z "$REGION" || -z "$OUT_DIR" ]]; then
  usage
  exit 64
fi
if [[ ! "$REGION" =~ ^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$ ]]; then
  echo "invalid AWS region: $REGION" >&2
  echo "example: eu-west-1" >&2
  exit 64
fi
case "$OUT_DIR" in
  ""|"/")
    echo "unsafe --out-dir: $OUT_DIR" >&2
    exit 64
    ;;
esac
if [[ ! "$MAX_RESULTS" =~ ^[0-9]+$ ]]; then
  echo "--max-results must be an integer from 1 to 50" >&2
  exit 64
fi

MAX_RESULTS_NUM=$((10#$MAX_RESULTS))

if (( MAX_RESULTS_NUM < 1 || MAX_RESULTS_NUM > 50 )); then
  echo "--max-results must be an integer from 1 to 50" >&2
  exit 64
fi

MAX_RESULTS="$MAX_RESULTS_NUM"

if ! command -v aws >/dev/null 2>&1; then
  echo "missing required command: aws" >&2
  exit 1
fi

lookup_time_args=()
if [[ -n "$START_TIME" ]]; then
  lookup_time_args+=(--start-time "$START_TIME")
fi
if [[ -n "$END_TIME" ]]; then
  lookup_time_args+=(--end-time "$END_TIME")
fi

mkdir -p "$OUT_DIR"

run_capture() {
  local name="$1"
  shift
  set +e
  "$@" > "$OUT_DIR/${name}.json" 2> "$OUT_DIR/${name}.stderr"
  local ec=$?
  set -e
  printf '%s\n' "$ec" > "$OUT_DIR/${name}.exitcode"
  if [[ "$ec" -eq 130 ]]; then
    echo "Interrupted while collecting ${name}; stopping." >&2
    exit 130
  fi
  if [[ "$ec" -ne 0 ]]; then
    echo "[WARN] ${name} failed with exit code ${ec}; see ${name}.stderr" >&2
  fi
}

run_text() {
  local name="$1"
  shift
  set +e
  "$@" > "$OUT_DIR/${name}.txt" 2> "$OUT_DIR/${name}.stderr"
  local ec=$?
  set -e
  printf '%s\n' "$ec" > "$OUT_DIR/${name}.exitcode"
  if [[ "$ec" -eq 130 ]]; then
    echo "Interrupted while collecting ${name}; stopping." >&2
    exit 130
  fi
  if [[ "$ec" -ne 0 ]]; then
    echo "[WARN] ${name} failed with exit code ${ec}; see ${name}.stderr" >&2
  fi
}

write_json_note() {
  local name="$1"
  local message="$2"

  printf '{\n  "note": "%s"\n}\n' "$message" > "$OUT_DIR/${name}.json"
  printf '0\n' > "$OUT_DIR/${name}.exitcode"
  : > "$OUT_DIR/${name}.stderr"
}

lookup_source() {
  local name="$1"
  local source="$2"
  run_capture "$name" \
    aws cloudtrail lookup-events \
      --lookup-attributes "AttributeKey=EventSource,AttributeValue=${source}" \
      --region "$REGION" \
      --max-results "$MAX_RESULTS" \
      "${lookup_time_args[@]}" \
      --output json
}

run_capture aws-caller-identity aws sts get-caller-identity --region "$REGION" --output json

run_text aws-cli-version aws --version

run_capture assume-role-with-web-identity-events \
  aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
    --region "$REGION" \
    --max-results "$MAX_RESULTS" \
    "${lookup_time_args[@]}" \
    --output json

lookup_source iam-events iam.amazonaws.com
lookup_source ec2-events ec2.amazonaws.com
lookup_source elbv2-events elasticloadbalancing.amazonaws.com
lookup_source autoscaling-events autoscaling.amazonaws.com
lookup_source s3-management-events s3.amazonaws.com
lookup_source cloudtrail-events cloudtrail.amazonaws.com

run_capture cloudtrail-trails \
  aws cloudtrail describe-trails \
    --region "$REGION" \
    --include-shadow-trails \
    --output json

if [[ -n "$TRAIL_NAME" ]]; then
  run_capture cloudtrail-event-selectors \
    aws cloudtrail get-event-selectors \
      --region "$REGION" \
      --trail-name "$TRAIL_NAME" \
      --output json
else
  write_json_note cloudtrail-event-selectors "not collected; pass --trail-name to query CloudTrail event selectors"
fi

run_capture recent-events \
  aws cloudtrail lookup-events \
    --region "$REGION" \
    --max-results "$MAX_RESULTS" \
    "${lookup_time_args[@]}" \
    --output json

valid_denied_inputs=()
for candidate in \
  assume-role-with-web-identity-events \
  iam-events \
  ec2-events \
  elbv2-events \
  autoscaling-events \
  s3-management-events \
  cloudtrail-events \
  recent-events; do
  if [[ "$(cat "$OUT_DIR/${candidate}.exitcode")" == "0" ]] \
    && [[ -s "$OUT_DIR/${candidate}.json" ]] \
    && command -v jq >/dev/null 2>&1 \
    && jq empty "$OUT_DIR/${candidate}.json" >/dev/null 2>&1; then
    valid_denied_inputs+=("$OUT_DIR/${candidate}.json")
  fi
done

if command -v jq >/dev/null 2>&1 && ((${#valid_denied_inputs[@]} > 0)); then
  jq -s '
    map(.Events[]? // empty)
    | map(select((.CloudTrailEvent | tostring) | test("AccessDenied|UnauthorizedOperation|Access Denied")))
  ' "${valid_denied_inputs[@]}" > "$OUT_DIR/denied-events.json" || printf '[]\n' > "$OUT_DIR/denied-events.json"
else
  printf '[]\n' > "$OUT_DIR/denied-events.json"
fi

cat > "$OUT_DIR/cloudtrail-summary.md" <<SUMMARY
# CloudTrail Audit Snapshot

- Captured UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Region: ${REGION}
- Release ID: ${RELEASE_ID}
- Workflow URL: ${WORKFLOW_URL}
- State bucket: ${STATE_BUCKET:-n/a}
- State prefix: ${STATE_PREFIX:-n/a}
- Trail name: ${TRAIL_NAME:-n/a}
- Max results per lookup: ${MAX_RESULTS}
- Start time: ${START_TIME:-n/a}
- End time: ${END_TIME:-n/a}

## Files

- aws-caller-identity.json
- aws-cli-version.txt
- assume-role-with-web-identity-events.json
- iam-events.json
- ec2-events.json
- elbv2-events.json
- autoscaling-events.json
- s3-management-events.json
- cloudtrail-events.json
- cloudtrail-trails.json
- cloudtrail-event-selectors.json
- recent-events.json
- denied-events.json

SUMMARY

echo "CloudTrail audit snapshot: $OUT_DIR"
