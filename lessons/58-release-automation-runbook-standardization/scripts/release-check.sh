#!/usr/bin/env bash
# Description: Standard release check (load + snapshots + build sampling + GO/HOLD/ROLLBACK).
# Usage: release-check.sh [--mode baseline|canary] [--tf-dir DIR] [--alb-url URL] [--out-root DIR] [--checkpoint-pct N] [--require-checkpoint]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  release-check.sh [--mode baseline|canary] [--tf-dir DIR] [--alb-url URL] [--out-root DIR] [--checkpoint-pct N] [--require-checkpoint]

Options:
  --mode      baseline or canary (default: canary)
  --tf-dir    terraform env directory with outputs (default: current dir)
  --alb-url   override ALB URL (example: http://127.0.0.1:18080/)
  --out-root  artifacts root directory (default: /tmp)
  --checkpoint-pct expected checkpoint percentage for canary checks (default: 50)
  --require-checkpoint fail canary run if latest refresh is not at expected checkpoint
  -h, --help  show help

Examples:
  ./lessons/58-release-automation-runbook-standardization/scripts/release-check.sh --mode baseline
  ./lessons/58-release-automation-runbook-standardization/scripts/release-check.sh --mode canary --out-root /tmp
  ./lessons/58-release-automation-runbook-standardization/scripts/release-check.sh --mode canary --require-checkpoint
  ./lessons/58-release-automation-runbook-standardization/scripts/release-check.sh --mode canary --alb-url http://127.0.0.1:18080/
USAGE
}

MODE="canary"
TF_DIR="$(pwd)"
ALB_URL=""
OUT_ROOT="/tmp"
CHECKPOINT_PCT="50"
REQUIRE_CHECKPOINT=0

# Parse CLI flags as key-value style options.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || { echo "ERROR: --mode requires value" >&2; exit 2; }
      MODE="$2"
      shift 2
      ;;
    --tf-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --tf-dir requires value" >&2; exit 2; }
      TF_DIR="$2"
      shift 2
      ;;
    --alb-url)
      [[ $# -ge 2 ]] || { echo "ERROR: --alb-url requires value" >&2; exit 2; }
      ALB_URL="$2"
      shift 2
      ;;
    --out-root)
      [[ $# -ge 2 ]] || { echo "ERROR: --out-root requires value" >&2; exit 2; }
      OUT_ROOT="$2"
      shift 2
      ;;
    --checkpoint-pct)
      [[ $# -ge 2 ]] || { echo "ERROR: --checkpoint-pct requires value" >&2; exit 2; }
      CHECKPOINT_PCT="$2"
      shift 2
      ;;
    --require-checkpoint)
      REQUIRE_CHECKPOINT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ "$MODE" != "baseline" && "$MODE" != "canary" ]]; then
  echo "ERROR: --mode must be baseline or canary" >&2
  exit 2
fi
[[ "$CHECKPOINT_PCT" =~ ^[0-9]+$ ]] || { echo "ERROR: --checkpoint-pct must be integer" >&2; exit 2; }
(( CHECKPOINT_PCT >= 0 && CHECKPOINT_PCT <= 100 )) || { echo "ERROR: --checkpoint-pct must be in range 0..100" >&2; exit 2; }

# Keep hard dependencies explicit so failures happen early.
for cmd in terraform aws curl awk sed date xargs mkdir; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

cd "$TF_DIR"

# Read canonical runtime identifiers from terraform outputs.
ASG_NAME="$(terraform output -raw web_asg_name)"
TG_ARN="$(terraform output -raw web_tg_arn)"
ALB_DNS="$(terraform output -raw alb_dns_name)"
PROJECT="$(terraform output -raw web_asg_name | sed 's/-web-asg$//')"

if [[ -z "$ALB_URL" ]]; then
  ALB_URL="http://${ALB_DNS}/"
fi
if [[ "$ALB_URL" != */ ]]; then
  # Normalize URL so downstream requests can safely append paths without worrying about missing slash.
  ALB_URL="${ALB_URL}/"
fi

DURATION=300
if [[ "$MODE" == "baseline" ]]; then
  # Baseline is intentionally shorter than canary.
  DURATION=180
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${OUT_ROOT}/l58-${MODE}-${STAMP}"
mkdir -p "$OUT_DIR"

echo "[INFO] mode=$MODE duration=${DURATION}s"
echo "[INFO] ASG=$ASG_NAME"
echo "[INFO] TG=$TG_ARN"
echo "[INFO] ALB_URL=$ALB_URL"
echo "[INFO] PROJECT=$PROJECT"
echo "[INFO] out_dir=$OUT_DIR"

capture_json() {
  local outfile="$1"
  shift
  # Do not fail the whole run on a single AWS API issue; keep placeholders.
  if "$@" >"$outfile" 2>"${outfile}.err"; then
    rm -f "${outfile}.err"
  else
    echo "[WARN] command failed, see ${outfile}.err" >&2
    echo "{}" >"$outfile"
  fi
}

alarm_state() {
  local name="$1"
  aws cloudwatch describe-alarms \
    --alarm-names "$name" \
    --query 'MetricAlarms[0].StateValue' \
    --output text 2>/dev/null || echo "UNKNOWN"
}

refresh_field() {
  local query="$1"
  # Read latest instance refresh state; used for checkpoint awareness.
  aws autoscaling describe-instance-refreshes \
    --auto-scaling-group-name "$ASG_NAME" \
    --max-records 1 \
    --query "$query" \
    --output text 2>/dev/null || echo "UNKNOWN"
}

REFRESH_STATUS="$(refresh_field 'InstanceRefreshes[0].Status')"
REFRESH_PCT="$(refresh_field 'InstanceRefreshes[0].PercentageComplete')"
REFRESH_REASON="$(refresh_field 'InstanceRefreshes[0].StatusReason')"
CHECKPOINT_MATCH=0
if [[ "$REFRESH_STATUS" == "InProgress" && "$REFRESH_PCT" =~ ^[0-9]+$ && "$REFRESH_PCT" -eq "$CHECKPOINT_PCT" ]]; then
  # Canary should ideally run while rollout is paused exactly at checkpoint.
  CHECKPOINT_MATCH=1
fi

echo "[INFO] latest_refresh_status=$REFRESH_STATUS"
echo "[INFO] latest_refresh_pct=$REFRESH_PCT"
echo "[INFO] latest_refresh_reason=$REFRESH_REASON"

if [[ "$MODE" == "canary" ]]; then
  echo "[INFO] canary checkpoint expectation=${CHECKPOINT_PCT}%"
  if (( ! CHECKPOINT_MATCH )); then
    echo "[WARN] latest instance refresh is not at expected checkpoint (${CHECKPOINT_PCT}%)" >&2
    if (( REQUIRE_CHECKPOINT )); then
      # Strict mode for drills: refuse canary outside checkpoint window.
      echo "[FAIL] --require-checkpoint enabled, aborting canary run" >&2
      exit 3
    fi
  fi
fi

# 1) Load phase (baseline/canary).
LOAD_LOG="$OUT_DIR/load.log"
END_TS="$(( $(date +%s) + DURATION ))"
echo "[INFO] load phase started"
while [[ "$(date +%s)" -lt "$END_TS" ]]; do
  # Parallel curls emulate moderate load; per-request timeout avoids hangs.
  seq 1 80 | xargs -P20 -I{} \
    curl -s --connect-timeout 1 --max-time 2 -o /dev/null -w "%{http_code} %{time_total}\n" "$ALB_URL" || true
done >>"$LOAD_LOG"
echo "[INFO] load phase completed"

awk '
$1 ~ /^2/ {ok++; t+=$2}
$1 !~ /^2/ {bad++}
END {
  total = ok + bad
  avg = (ok ? t / ok : 0)
  printf "total=%d ok=%d bad=%d avg=%.3fs\n", total, ok, bad, avg
}' "$LOAD_LOG" | tee "$OUT_DIR/load.summary.txt"

awk '{codes[$1]++} END {for (c in codes) printf "%s %d\n", c, codes[c]}' "$LOAD_LOG" | sort >"$OUT_DIR/load.codes.txt"

# Extra counters let decision logic detect "no path to ALB" cases.
TOTAL_SAMPLES="$(awk '{c++} END {print c+0}' "$LOAD_LOG")"
OK_SAMPLES="$(awk '$1 ~ /^2/ {c++} END {print c+0}' "$LOAD_LOG")"
BAD_SAMPLES="$(( TOTAL_SAMPLES - OK_SAMPLES ))"
ZERO_HTTP_SAMPLES="$(awk '$1 == "000" {c++} END {print c+0}' "$LOAD_LOG")"

# 2) Snapshot phase.
capture_json "$OUT_DIR/alarms.json" aws cloudwatch describe-alarms \
  --alarm-names \
    "${PROJECT}-target-5xx-critical" \
    "${PROJECT}-alb-unhealthy-hosts" \
    "${PROJECT}-release-target-5xx" \
    "${PROJECT}-release-latency" \
  --output json

capture_json "$OUT_DIR/target-health.json" aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --output json

capture_json "$OUT_DIR/instance-refreshes.json" aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 10 \
  --output json

capture_json "$OUT_DIR/scaling-activities.json" aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-items 30 \
  --output json

# 3) Build identity sampler.
# Use "_" because loop index itself is intentionally unused.
for _ in {1..80}; do
  curl -s --connect-timeout 1 --max-time 2 -H 'Connection: close' "${ALB_URL}" | grep -Ei 'BUILD|Hostname|InstanceId' || true
done >"$OUT_DIR/build-sampler.txt"

# 4) Decision phase.
SAFETY_5XX="$(alarm_state "${PROJECT}-target-5xx-critical")"
SAFETY_UNH="$(alarm_state "${PROJECT}-alb-unhealthy-hosts")"
REL_5XX="$(alarm_state "${PROJECT}-release-target-5xx")"
REL_LAT="$(alarm_state "${PROJECT}-release-latency")"

DECISION="GO"
REASON="all gates OK"
EXIT_CODE=0

# Decision priority:
# 1) safety alarms (hard rollback)
# 2) quality alarms (rollback/hold)
# 3) transport sanity checks from load results
if [[ "$SAFETY_5XX" == "ALARM" || "$SAFETY_UNH" == "ALARM" ]]; then
  DECISION="ROLLBACK"
  REASON="safety alarm triggered"
  EXIT_CODE=2
elif [[ "$REL_5XX" == "ALARM" ]]; then
  DECISION="ROLLBACK"
  REASON="release 5xx gate triggered"
  EXIT_CODE=2
elif [[ "$REL_LAT" == "ALARM" ]]; then
  DECISION="HOLD"
  REASON="release latency gate triggered"
  EXIT_CODE=1
elif (( TOTAL_SAMPLES == 0 )); then
  DECISION="HOLD"
  REASON="no load samples collected"
  EXIT_CODE=1
elif (( OK_SAMPLES == 0 )); then
  DECISION="HOLD"
  REASON="no successful HTTP responses; check ALB reachability (proxy/SSM port-forward)"
  EXIT_CODE=1
fi

{
  echo "mode=$MODE"
  echo "decision=$DECISION"
  echo "reason=$REASON"
  echo "load_total=$TOTAL_SAMPLES"
  echo "load_ok=$OK_SAMPLES"
  echo "load_bad=$BAD_SAMPLES"
  echo "load_http_000=$ZERO_HTTP_SAMPLES"
  echo "safety_5xx=$SAFETY_5XX"
  echo "safety_unhealthy=$SAFETY_UNH"
  echo "release_5xx=$REL_5XX"
  echo "release_latency=$REL_LAT"
  echo "refresh_status=$REFRESH_STATUS"
  echo "refresh_pct=$REFRESH_PCT"
  echo "checkpoint_expected_pct=$CHECKPOINT_PCT"
  echo "checkpoint_match=$CHECKPOINT_MATCH"
  echo "timestamp=$(date -Is)"
} | tee "$OUT_DIR/decision.txt"

cat >"$OUT_DIR/summary.json" <<JSON
{
  "mode": "$MODE",
  "decision": "$DECISION",
  "reason": "$REASON",
  "load_total": $TOTAL_SAMPLES,
  "load_ok": $OK_SAMPLES,
  "load_bad": $BAD_SAMPLES,
  "load_http_000": $ZERO_HTTP_SAMPLES,
  "asg_name": "$ASG_NAME",
  "tg_arn": "$TG_ARN",
  "alb_url": "$ALB_URL",
  "project": "$PROJECT",
  "safety_5xx": "$SAFETY_5XX",
  "safety_unhealthy": "$SAFETY_UNH",
  "release_5xx": "$REL_5XX",
  "release_latency": "$REL_LAT",
  "refresh_status": "$REFRESH_STATUS",
  "refresh_pct": "$REFRESH_PCT",
  "checkpoint_expected_pct": "$CHECKPOINT_PCT",
  "checkpoint_match": $CHECKPOINT_MATCH,
  "timestamp": "$(date -Is)"
}
JSON

# Exit code contract:
# 0=GO, 1=HOLD, 2=ROLLBACK, 3=canary aborted (checkpoint required)
echo "[RESULT] DECISION=$DECISION"
echo "[RESULT] artifacts=$OUT_DIR"

exit "$EXIT_CODE"
