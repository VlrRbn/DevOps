#!/usr/bin/env bash
# Description: Generate release-note.md + release-note.json from lesson 58 artifact folders.
# Usage: release-note-gen.sh --artifact-dir DIR [--baseline-dir DIR] [--out-dir DIR] [--release-id ID] [--why TEXT] [--env NAME] [--redact]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  release-note-gen.sh --artifact-dir DIR [--baseline-dir DIR] [--out-dir DIR] [--release-id ID] [--why TEXT] [--env NAME] [--redact]

Examples:
  lessons/59-change-management-release-notes/scripts/release-note-gen.sh \
    --artifact-dir lessons/58-release-automation-runbook-standardization/evidence/l58-canary-20260303_195546 \
    --baseline-dir lessons/58-release-automation-runbook-standardization/evidence/l58-baseline-20260303_194433 \
    --out-dir lessons/59-change-management-release-notes/evidence/l59-20260318_01 \
    --why "Promote candidate after checkpoint canary" \
    --env lab57

  lessons/59-change-management-release-notes/scripts/release-note-gen.sh \
    --artifact-dir /tmp/l58-canary-20260303_195546 \
    --out-dir /tmp/l59-public-note \
    --redact
USAGE
}

ARTIFACT_DIR=""
BASELINE_DIR=""
OUT_DIR=""
RELEASE_ID=""
WHY_TEXT=""
ENV_NAME=""
REDACT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --artifact-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --artifact-dir requires value" >&2; exit 2; }
      ARTIFACT_DIR="$2"
      shift 2
      ;;
    --baseline-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --baseline-dir requires value" >&2; exit 2; }
      BASELINE_DIR="$2"
      shift 2
      ;;
    --out-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --out-dir requires value" >&2; exit 2; }
      OUT_DIR="$2"
      shift 2
      ;;
    --release-id)
      [[ $# -ge 2 ]] || { echo "ERROR: --release-id requires value" >&2; exit 2; }
      RELEASE_ID="$2"
      shift 2
      ;;
    --why)
      [[ $# -ge 2 ]] || { echo "ERROR: --why requires value" >&2; exit 2; }
      WHY_TEXT="$2"
      shift 2
      ;;
    --env)
      [[ $# -ge 2 ]] || { echo "ERROR: --env requires value" >&2; exit 2; }
      ENV_NAME="$2"
      shift 2
      ;;
    --redact)
      REDACT=1
      shift
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[[ -n "$ARTIFACT_DIR" ]] || { echo "ERROR: --artifact-dir is required" >&2; exit 2; }
[[ -d "$ARTIFACT_DIR" ]] || { echo "ERROR: artifact dir not found: $ARTIFACT_DIR" >&2; exit 2; }

# Keep dependency checks explicit so failures are clear.
for cmd in awk sed grep sort paste date basename dirname jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

# These files are the minimum artifact contract exported by lesson 58.
required_files=(
  decision.txt
  summary.json
  load.summary.txt
  alarms.json
  target-health.json
  instance-refreshes.json
  build-sampler.txt
)
for f in "${required_files[@]}"; do
  [[ -f "$ARTIFACT_DIR/$f" ]] || { echo "ERROR: required file missing: $ARTIFACT_DIR/$f" >&2; exit 1; }
done

if [[ -n "$BASELINE_DIR" ]]; then
  [[ -d "$BASELINE_DIR" ]] || { echo "ERROR: baseline dir not found: $BASELINE_DIR" >&2; exit 2; }
  [[ -f "$BASELINE_DIR/load.summary.txt" ]] || { echo "ERROR: baseline file missing: $BASELINE_DIR/load.summary.txt" >&2; exit 1; }
  [[ -f "$BASELINE_DIR/build-sampler.txt" ]] || { echo "ERROR: baseline file missing: $BASELINE_DIR/build-sampler.txt" >&2; exit 1; }
fi

# If caller does not provide --out-dir, write note files next to canary artifacts.
if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$ARTIFACT_DIR"
fi
mkdir -p "$OUT_DIR"

# Read first matching key=value from decision.txt.
read_kv() {
  local file="$1"
  local key="$2"
  awk -F= -v k="$key" '$1==k{print substr($0,index($0,"=")+1); exit}' "$file"
}

# Parse load.summary.txt format: "total=100 ok=95 bad=5 avg=0.123s".
parse_load_summary() {
  local file="$1"
  awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^total=/) { sub(/^total=/, "", $i); total = $i }
        if ($i ~ /^ok=/)    { sub(/^ok=/, "", $i); ok = $i }
        if ($i ~ /^bad=/)   { sub(/^bad=/, "", $i); bad = $i }
        if ($i ~ /^avg=/)   { sub(/^avg=/, "", $i); avg = $i; sub(/s$/, "", avg) }
      }
    }
    END {
      if (total == "") total = 0
      if (ok == "") ok = 0
      if (bad == "") bad = 0
      if (avg == "") avg = 0
      printf "%s %s %s %s\n", total, ok, bad, avg
    }
  ' "$file"
}

# Add "s" only for numeric averages; keep "n/a" untouched.
format_avg() {
  local value="$1"
  if [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "${value}s"
  else
    echo "$value"
  fi
}

# build-sampler.txt has repeated BUILD_ID lines; keep unique values only.
extract_builds() {
  local file="$1"
  local builds
  builds="$({ grep -oE 'BUILD_ID:[[:space:]]*[^<[:space:]]+' "$file" || true; } | sed -E 's/BUILD_ID:[[:space:]]*//' | sort -u | paste -sd ',' -)"
  if [[ -z "$builds" ]]; then
    echo "unknown"
  else
    echo "$builds"
  fi
}

# Redaction rules are intentionally text-based, so they work for both .md and .json outputs.
redact_stream() {
  sed -E \
    -e 's/arn:aws:([^:]+):([^:]*):[0-9]{12}:/arn:aws:\1:\2:<account-id>:/g' \
    -e 's/\bi-[0-9a-f]{8,17}\b/<instance-id>/g' \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<ip>/g' \
    -e 's/(app|targetgroup)\/[A-Za-z0-9.-]+\/[A-Za-z0-9]+/\1\/<resource>\/<hash>/g'
}

# Convenience wrapper to redact one scalar value only when --redact is enabled.
maybe_redact_value() {
  if (( REDACT )); then
    printf '%s' "$1" | redact_stream
  else
    printf '%s' "$1"
  fi
}

decision_file="$ARTIFACT_DIR/decision.txt"
summary_file="$ARTIFACT_DIR/summary.json"

# decision.txt is primary source; summary.json is fallback for compatibility.
decision="$(read_kv "$decision_file" decision)"
reason="$(read_kv "$decision_file" reason)"
timestamp="$(read_kv "$decision_file" timestamp)"
[[ -n "$decision" ]] || decision="$(jq -r '.decision // "UNKNOWN"' "$summary_file")"
[[ -n "$reason" ]] || reason="$(jq -r '.reason // "not provided"' "$summary_file")"
[[ -n "$timestamp" ]] || timestamp="$(date -u '+%FT%TZ')"

asg_name="$(jq -r '.asg_name // "unknown"' "$summary_file")"
tg_arn="$(jq -r '.tg_arn // "unknown"' "$summary_file")"
alb_url="$(jq -r '.alb_url // "unknown"' "$summary_file")"
project="$(jq -r '.project // "unknown"' "$summary_file")"

# Canary metrics come from --artifact-dir. Baseline is optional.
read -r canary_total canary_ok canary_bad canary_avg < <(parse_load_summary "$ARTIFACT_DIR/load.summary.txt")

if [[ -n "$BASELINE_DIR" ]]; then
  read -r baseline_total baseline_ok baseline_bad baseline_avg < <(parse_load_summary "$BASELINE_DIR/load.summary.txt")
else
  baseline_total="n/a"
  baseline_ok="n/a"
  baseline_bad="n/a"
  baseline_avg="n/a"
fi

baseline_avg_disp="$(format_avg "$baseline_avg")"
canary_avg_disp="$(format_avg "$canary_avg")"

# BUILD_ID distribution helps explain mixed fleet at checkpoint.
candidate_builds="$(extract_builds "$ARTIFACT_DIR/build-sampler.txt")"
if [[ -n "$BASELINE_DIR" ]]; then
  previous_builds="$(extract_builds "$BASELINE_DIR/build-sampler.txt")"
else
  previous_builds="unknown"
fi

if [[ -z "$ENV_NAME" ]]; then
  ENV_NAME="$project"
fi
if [[ -z "$WHY_TEXT" ]]; then
  WHY_TEXT="Promote candidate based on release gate evidence"
fi
if [[ -z "$RELEASE_ID" ]]; then
  RELEASE_ID="$(basename "$ARTIFACT_DIR")"
fi

# References are printed in note footer; can be replaced in redact mode.
artifact_ref="$ARTIFACT_DIR"
baseline_ref="${BASELINE_DIR:-n/a}"

# Render compact markdown table from CloudWatch alarm snapshot.
alarms_table_md="$({
  echo "| Alarm | State |"
  echo "|---|---|"
  jq -r '.MetricAlarms[]? | "| \(.AlarmName) | \(.StateValue) |"' "$ARTIFACT_DIR/alarms.json"
} || true)"
if [[ "$(printf '%s' "$alarms_table_md" | wc -l)" -le 2 ]]; then
  alarms_table_md=$'| Alarm | State |\n|---|---|\n| n/a | n/a |'
fi

# Target state table is a key "why" input for GO/HOLD/ROLLBACK decisions.
target_health_table_md="$({
  echo "| Target | State | Reason |"
  echo "|---|---|---|"
  jq -r '.TargetHealthDescriptions[]? | "| \(.Target.Id) | \(.TargetHealth.State) | \(.TargetHealth.Reason // "") |"' "$ARTIFACT_DIR/target-health.json"
} || true)"
if [[ "$(printf '%s' "$target_health_table_md" | wc -l)" -le 2 ]]; then
  target_health_table_md=$'| Target | State | Reason |\n|---|---|---|\n| n/a | n/a | n/a |'
fi

refresh_status="$(jq -r '.InstanceRefreshes[0].Status // "None"' "$ARTIFACT_DIR/instance-refreshes.json")"
refresh_pct="$(jq -r '.InstanceRefreshes[0].PercentageComplete // "n/a"' "$ARTIFACT_DIR/instance-refreshes.json")"
refresh_reason="$(jq -r '.InstanceRefreshes[0].StatusReason // ""' "$ARTIFACT_DIR/instance-refreshes.json")"
instance_refresh_summary="status=${refresh_status}; percentage=${refresh_pct}; reason=${refresh_reason}"

# Map decision to operator actions so note is immediately actionable.
case "$decision" in
  GO)
    decision_rationale="Decision is GO because gates are healthy and canary evidence is stable. Source reason: ${reason}."
    actions=$'- Continue rollout to 100%.\n- Monitor alarms and target health for 10 minutes.\n- Attach this note to release record/PR.'
    ;;
  HOLD)
    decision_rationale="Decision is HOLD because quality risk requires investigation before full rollout. Source reason: ${reason}."
    actions=$'- Keep rollout paused at checkpoint.\n- Investigate latency/error signals using referenced artifacts.\n- Re-run canary after mitigation.'
    ;;
  ROLLBACK)
    decision_rationale="Decision is ROLLBACK because safety or severe quality signal triggered rollback criteria. Source reason: ${reason}."
    actions=$'- Revert AMI/config to last known good.\n- Apply and verify alarms return to OK.\n- Record rollback completion timestamp.'
    ;;
  *)
    decision_rationale="Decision is ${decision}. Source reason: ${reason}."
    actions=$'- Review inputs and decide next operational step.'
    ;;
esac

# Apply redaction to final rendered fields, not to source artifacts.
if (( REDACT )); then
  asg_name="$(maybe_redact_value "$asg_name")"
  tg_arn="$(maybe_redact_value "$tg_arn")"
  alb_url="$(maybe_redact_value "$alb_url")"
  candidate_builds="$(maybe_redact_value "$candidate_builds")"
  previous_builds="$(maybe_redact_value "$previous_builds")"
  instance_refresh_summary="$(maybe_redact_value "$instance_refresh_summary")"
  decision_rationale="$(maybe_redact_value "$decision_rationale")"
  actions="$(printf '%s' "$actions" | redact_stream)"
  alarms_table_md="$(printf '%s' "$alarms_table_md" | redact_stream)"
  target_health_table_md="$(printf '%s' "$target_health_table_md" | redact_stream)"
  artifact_ref="<redacted-path>"
  baseline_ref="<redacted-path>"
fi

note_md="$OUT_DIR/release-note.md"
note_json="$OUT_DIR/release-note.json"

# Markdown output is human-first (PR/review/on-call handoff).
cat > "$note_md" <<EOF_MD
# Release Note - ${RELEASE_ID}

## Metadata

- Timestamp (UTC): ${timestamp}
- Environment: ${ENV_NAME}
- Decision: **${decision}**
- ASG: ${asg_name}
- ALB URL: ${alb_url}
- Target Group: ${tg_arn}

## Change

- Candidate build(s): ${candidate_builds}
- Baseline/previous build(s): ${previous_builds}
- Why changed: ${WHY_TEXT}

## Risk Assessment

- Primary risks: 5xx regression, unhealthy targets, latency increase, rollout instability
- Rollback method: revert AMI/config and validate alarms + target health

## Evidence Summary
### Baseline

- total=${baseline_total} ok=${baseline_ok} bad=${baseline_bad} avg=${baseline_avg_disp}

### Canary

- total=${canary_total} ok=${canary_ok} bad=${canary_bad} avg=${canary_avg_disp}

### Alarm States

${alarms_table_md}

### Target Health

${target_health_table_md}

### Instance Refresh

${instance_refresh_summary}

## Decision Rationale

${decision_rationale}

## Actions

${actions}

## References

- Canary artifacts: ${artifact_ref}
- Baseline artifacts: ${baseline_ref}
EOF_MD

# JSON output is machine-first (parsing, automation, archival queries).
jq -n \
  --arg release_id "$RELEASE_ID" \
  --arg timestamp_utc "$timestamp" \
  --arg env "$ENV_NAME" \
  --arg decision "$decision" \
  --arg asg_name "$asg_name" \
  --arg alb_url "$alb_url" \
  --arg tg_arn "$tg_arn" \
  --arg candidate_builds "$candidate_builds" \
  --arg previous_builds "$previous_builds" \
  --arg why "$WHY_TEXT" \
  --arg baseline_total "$baseline_total" \
  --arg baseline_ok "$baseline_ok" \
  --arg baseline_bad "$baseline_bad" \
  --arg baseline_avg "$baseline_avg" \
  --arg canary_total "$canary_total" \
  --arg canary_ok "$canary_ok" \
  --arg canary_bad "$canary_bad" \
  --arg canary_avg "$canary_avg" \
  --arg refresh_status "$refresh_status" \
  --arg refresh_pct "$refresh_pct" \
  --arg refresh_reason "$refresh_reason" \
  --arg rationale "$decision_rationale" \
  --arg actions "$actions" \
  --arg artifact_dir "$ARTIFACT_DIR" \
  --arg baseline_dir "${BASELINE_DIR:-}" \
  --arg generated_at "$(date -u '+%FT%TZ')" \
  --argjson alarms "$(jq '.MetricAlarms // []' "$ARTIFACT_DIR/alarms.json")" \
  --argjson target_health "$(jq '.TargetHealthDescriptions // []' "$ARTIFACT_DIR/target-health.json")" \
  '{
    release_id: $release_id,
    generated_at: $generated_at,
    metadata: {
      timestamp_utc: $timestamp_utc,
      environment: $env,
      decision: $decision,
      asg_name: $asg_name,
      alb_url: $alb_url,
      target_group_arn: $tg_arn
    },
    change: {
      candidate_builds: $candidate_builds,
      previous_builds: $previous_builds,
      why: $why
    },
    evidence: {
      baseline: {
        total: $baseline_total,
        ok: $baseline_ok,
        bad: $baseline_bad,
        avg_seconds: $baseline_avg
      },
      canary: {
        total: $canary_total,
        ok: $canary_ok,
        bad: $canary_bad,
        avg_seconds: $canary_avg
      },
      alarms: $alarms,
      target_health: $target_health,
      instance_refresh: {
        status: $refresh_status,
        percentage_complete: $refresh_pct,
        reason: $refresh_reason
      }
    },
    decision: {
      result: $decision,
      rationale: $rationale,
      actions: $actions
    },
    references: {
      canary_artifact_dir: $artifact_dir,
      baseline_artifact_dir: (if $baseline_dir == "" then null else $baseline_dir end)
    }
  }' > "$note_json"

if (( REDACT )); then
  # Replace reference paths with placeholders for public-share mode.
  jq '.references.canary_artifact_dir = "<redacted-path>" | .references.baseline_artifact_dir = (if .references.baseline_artifact_dir == null then null else "<redacted-path>" end)' "$note_json" > "$note_json.tmp"
  mv "$note_json.tmp" "$note_json"
  # Redact common sensitive tokens in all JSON string fields.
  redact_stream < "$note_json" > "$note_json.tmp"
  mv "$note_json.tmp" "$note_json"
fi

echo "[OK] generated: $note_md"
echo "[OK] generated: $note_json"
