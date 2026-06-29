#!/usr/bin/env bash
set -Eeuo pipefail

# Final apply risk classifier.
#
# Earlier scripts answer narrower questions:
# - security-policy.sh: is the change allowed by security policy?
# - cost-policy.sh: is the change allowed by cost/blast-radius policy?
#
# This script combines those outputs with environment context, promotion evidence,
# incident mode, and Terraform plan action counts. Its output is the final
# review artifact that an apply pipeline should show before approval.
#
# Important safety model:
# - fail closed when required policy/cost inputs are missing or malformed;
# - BLOCKED always wins over other risk levels;
# - EMERGENCY requires an incident record and does not bypass deny findings;
# - stage/prod managed changes require valid promotion evidence unless this is incident mode;
# - NO_CHANGE is allowed only after a valid Terraform JSON plan and valid policy inputs are present.
usage() {
  cat >&2 <<'USAGE'
Usage:
  risk-classifier.sh <tfplan.json> <dev|stage|prod>

Environment variables:
  POLICY_DIR                    Directory with policy-deny.json and policy-warn.json. Default: policy-results
  COST_DIR                      Directory with cost-deny.json and cost-warn.json. Default: cost-policy-results
  OUT_DIR                       Output directory. Default: risk-results
  INCIDENT_MODE                 true/false. Default: false
  INCIDENT_RECORD_FILE          Required when INCIDENT_MODE=true
  RELEASE_ID                    Optional release/change identifier
  SOURCE_ENV                    Optional source environment for promotion evidence
  PROMOTION_EVIDENCE_FILE       Required for stage/prod managed changes unless INCIDENT_MODE=true
  REQUIRE_PROMOTION_EVIDENCE    true/false. Default: true
  ALLOW_MISSING_POLICY_OUTPUTS  true/false. Default: false

Exit codes:
  0  classified and apply is allowed by risk gate
  1  input/tooling error
  2  blocked by risk gate
  64 usage/input shape error
USAGE
}

PLAN_JSON="${1:-}"
TARGET_ENV="${2:-}"

# Do not default the target environment. Risk differs materially between dev,
# stage, and prod, so a missing env must be treated as usage error.
if [[ -z "$PLAN_JSON" || -z "$TARGET_ENV" ]]; then
  usage
  exit 64
fi

case "$TARGET_ENV" in
  dev|stage|prod) ;;
  *) echo "target_env must be one of: dev, stage, prod" >&2; exit 64 ;;
esac

# The script relies on Terraform JSON plan structure.
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for risk classification" >&2
  exit 1
fi

# A missing plan is tooling/input error, not a risk decision.
if [[ ! -f "$PLAN_JSON" ]]; then
  echo "PLAN_JSON not found: $PLAN_JSON" >&2
  exit 1
fi

# Reject arbitrary JSON early. Without this guard, `{}` would look like a plan
# with zero changes and could incorrectly become NO_CHANGE/apply_allowed=true.
if ! jq -e '
  type == "object"
  and (.resource_changes | type == "array")
  and all(.resource_changes[]?; (.mode | type == "string") and (.type | type == "string") and (.change.actions | type == "array"))
' "$PLAN_JSON" >/dev/null 2>&1; then
  echo "PLAN_JSON is not a valid Terraform JSON plan with resource_changes[].change.actions." >&2
  exit 64
fi

# Environment variables are optional inputs for local drills and CI integration.
# Defaults are chosen to be safe for production-like use:
# - promotion evidence is required by default;
# - missing policy outputs are not allowed by default.
POLICY_DIR="${POLICY_DIR:-policy-results}"
COST_DIR="${COST_DIR:-cost-policy-results}"
OUT_DIR="${OUT_DIR:-risk-results}"
INCIDENT_MODE="${INCIDENT_MODE:-false}"
INCIDENT_RECORD_FILE="${INCIDENT_RECORD_FILE:-}"
RELEASE_ID="${RELEASE_ID:-}"
SOURCE_ENV="${SOURCE_ENV:-}"
PROMOTION_EVIDENCE_FILE="${PROMOTION_EVIDENCE_FILE:-}"
REQUIRE_PROMOTION_EVIDENCE="${REQUIRE_PROMOTION_EVIDENCE:-true}"
ALLOW_MISSING_POLICY_OUTPUTS="${ALLOW_MISSING_POLICY_OUTPUTS:-false}"

# Boolean-like environment variables must be strict.
case "$INCIDENT_MODE" in
  true|false) ;;
  *) echo "INCIDENT_MODE must be true or false" >&2; exit 64 ;;
esac

case "$REQUIRE_PROMOTION_EVIDENCE" in
  true|false) ;;
  *) echo "REQUIRE_PROMOTION_EVIDENCE must be true or false" >&2; exit 64 ;;
esac

case "$ALLOW_MISSING_POLICY_OUTPUTS" in
  true|false) ;;
  *) echo "ALLOW_MISSING_POLICY_OUTPUTS must be true or false" >&2; exit 64 ;;
esac

# CI must not allow the local/debug escape hatch.
if [[ "${GITHUB_ACTIONS:-false}" == "true" && "$ALLOW_MISSING_POLICY_OUTPUTS" == "true" ]]; then
  echo "ALLOW_MISSING_POLICY_OUTPUTS=true is forbidden in CI." >&2
  exit 64
fi

mkdir -p "$OUT_DIR"

# Output contract. JSON is for automation; Markdown is for operators/reviewers.
RISK_JSON="$OUT_DIR/risk-decision.json"
RISK_MD="$OUT_DIR/risk-decision.md"

input_reasons=()
JSON_ARRAY_LEN=0

# Read a policy/cost output file and expose its array length via JSON_ARRAY_LEN.
#
# This function is intentionally fail-closed by default.
# The only exception is ALLOW_MISSING_POLICY_OUTPUTS=true, which is allowed for
# local demonstrations but forbidden in GitHub Actions above.
json_array_len() {
  local file="$1"
  local label="$2"

  JSON_ARRAY_LEN=0

  if [[ ! -f "$file" ]]; then
    if [[ "$ALLOW_MISSING_POLICY_OUTPUTS" == "true" ]]; then
      return
    fi
    input_reasons+=("${label}_missing")
    return
  fi

  if ! jq -e 'type == "array"' "$file" >/dev/null 2>&1; then
    input_reasons+=("${label}_invalid_json_array")
    return
  fi

  JSON_ARRAY_LEN="$(jq 'length' "$file")"
}

# Load security policy outputs.
json_array_len "$POLICY_DIR/policy-deny.json" policy_deny
policy_deny_count="$JSON_ARRAY_LEN"
json_array_len "$POLICY_DIR/policy-warn.json" policy_warn
policy_warn_count="$JSON_ARRAY_LEN"

# Load cost/blast-radius policy outputs.
json_array_len "$COST_DIR/cost-deny.json" cost_deny
cost_deny_count="$JSON_ARRAY_LEN"
json_array_len "$COST_DIR/cost-warn.json" cost_warn
cost_warn_count="$JSON_ARRAY_LEN"

# Count important Terraform action classes. These counters drive risk level and
# give reviewers a quick reason summary without reading the full plan.
destructive_count="$(jq '[.resource_changes[]? | select(.mode == "managed") | select(.change.actions | index("delete"))] | length' "$PLAN_JSON")"
replacement_count="$(jq '[.resource_changes[]? | select(.mode == "managed") | select((.change.actions | index("delete")) and (.change.actions | index("create")))] | length' "$PLAN_JSON")"
iam_change_count="$(jq '[.resource_changes[]? | select(.mode == "managed") | select(.type | startswith("aws_iam_")) | select(.change.actions != ["no-op"])] | length' "$PLAN_JSON")"
asg_or_lt_change_count="$(jq '[.resource_changes[]? | select(.mode == "managed") | select(.type == "aws_autoscaling_group" or .type == "aws_launch_template") | select(.change.actions != ["no-op"])] | length' "$PLAN_JSON")"
changed_count="$(jq '[.resource_changes[]? | select(.mode == "managed") | select(.change.actions != ["no-op"])] | length' "$PLAN_JSON")"

# Promotion evidence must not be globally disabled in CI for real stage/prod changes.
# Local drills and dev demonstration artifacts can still disable it, and NO_CHANGE does not need promotion.
if [[ "${GITHUB_ACTIONS:-false}" == "true" && "$REQUIRE_PROMOTION_EVIDENCE" == "false" && "$changed_count" -gt 0 && ( "$TARGET_ENV" == "stage" || "$TARGET_ENV" == "prod" ) && "$INCIDENT_MODE" == "false" ]]; then
  echo "REQUIRE_PROMOTION_EVIDENCE=false is forbidden in CI for stage/prod managed changes." >&2
  exit 64
fi

promotion_required=false
promotion_present=false
promotion_valid=false

# Promotion evidence is required only when all conditions are true:
# - there are managed changes;
# - target is stage/prod;
# - this is not incident mode;
# - promotion evidence requirement was not intentionally disabled for local/dev.
if [[ "$changed_count" -gt 0 && "$REQUIRE_PROMOTION_EVIDENCE" == "true" && "$INCIDENT_MODE" == "false" && ( "$TARGET_ENV" == "stage" || "$TARGET_ENV" == "prod" ) ]]; then
  promotion_required=true
  if [[ -n "$PROMOTION_EVIDENCE_FILE" && -s "$PROMOTION_EVIDENCE_FILE" ]]; then
    promotion_present=true
    promotion_valid=true

    if ! jq -e 'type == "object"' "$PROMOTION_EVIDENCE_FILE" >/dev/null 2>&1; then
      promotion_valid=false
      input_reasons+=("promotion_evidence_invalid_json")
    else
      # Promotion evidence is a contract, not just a non-empty file. It should
      # prove that this change was promoted from the expected source environment
      # and that the previous gate actually passed.
      evidence_release_id="$(jq -r '.release_id // ""' "$PROMOTION_EVIDENCE_FILE")"
      evidence_source_env="$(jq -r '.source_env // ""' "$PROMOTION_EVIDENCE_FILE")"
      evidence_status="$(jq -r '.status // ""' "$PROMOTION_EVIDENCE_FILE")"
      evidence_commit_sha="$(jq -r '.commit_sha // ""' "$PROMOTION_EVIDENCE_FILE")"
      evidence_source_workflow_run_url="$(jq -r '.source_workflow_run_url // ""' "$PROMOTION_EVIDENCE_FILE")"

      if [[ -n "$RELEASE_ID" && "$evidence_release_id" != "$RELEASE_ID" ]]; then
        promotion_valid=false
        input_reasons+=("promotion_evidence_release_id_mismatch")
      fi

      if [[ -z "$evidence_release_id" ]]; then
        promotion_valid=false
        input_reasons+=("promotion_evidence_release_id_missing")
      fi

      if [[ -n "$SOURCE_ENV" && "$evidence_source_env" != "$SOURCE_ENV" ]]; then
        promotion_valid=false
        input_reasons+=("promotion_evidence_source_env_mismatch")
      fi

      if [[ -z "$evidence_source_env" ]]; then
        promotion_valid=false
        input_reasons+=("promotion_evidence_source_env_missing")
      fi

      if [[ "$evidence_status" != "passed" ]]; then
        promotion_valid=false
        input_reasons+=("promotion_evidence_status_not_passed")
      fi

      if [[ ! "$evidence_commit_sha" =~ ^[0-9a-f]{7,40}$ ]]; then
        promotion_valid=false
        input_reasons+=("promotion_evidence_commit_sha_invalid")
      fi

      if [[ -z "$evidence_source_workflow_run_url" ]]; then
        promotion_valid=false
        input_reasons+=("promotion_evidence_source_workflow_run_url_missing")
      elif [[ ! "$evidence_source_workflow_run_url" =~ ^https://github\.com/.+/actions/runs/[0-9]+(/.*)?$ ]]; then
        promotion_valid=false
        input_reasons+=("promotion_evidence_source_workflow_run_url_invalid")
      fi
    fi
  fi
fi

incident_record_required=false
incident_record_present=false

# Incident mode is a controlled break-glass path. It can change risk to EMERGENCY,
# but only if an incident record exists. It does not override policy/cost denies.
if [[ "$INCIDENT_MODE" == "true" ]]; then
  incident_record_required=true
  if [[ -n "$INCIDENT_RECORD_FILE" && -s "$INCIDENT_RECORD_FILE" ]]; then
    incident_record_present=true
  fi
fi

risk="LOW"
apply_allowed=true
approval_required=true
approval_level="standard"
reasons=()

# BLOCKED class: missing/malformed required inputs. This happens before ordinary
# risk escalation because unreliable inputs make any "allow" decision unsafe.
if [[ "${#input_reasons[@]}" -gt 0 ]]; then
  risk="BLOCKED"
  apply_allowed=false
  approval_required=false
  approval_level="none"
  reasons+=("${input_reasons[@]}")
fi

# BLOCKED class: a lower-level security or cost policy has hard deny findings.
if [[ "$policy_deny_count" -gt 0 || "$cost_deny_count" -gt 0 ]]; then
  risk="BLOCKED"
  apply_allowed=false
  approval_required=false
  approval_level="none"
  reasons+=("policy_or_cost_deny_present")
fi

# BLOCKED class: stage/prod needs promotion evidence for managed changes.
if [[ "$promotion_required" == "true" && "$promotion_present" == "false" ]]; then
  risk="BLOCKED"
  apply_allowed=false
  approval_required=false
  approval_level="none"
  reasons+=("promotion_evidence_missing")
fi

# BLOCKED class: evidence file exists but fails the evidence contract.
if [[ "$promotion_required" == "true" && "$promotion_present" == "true" && "$promotion_valid" == "false" ]]; then
  risk="BLOCKED"
  apply_allowed=false
  approval_required=false
  approval_level="none"
fi

# BLOCKED class: incident mode without incident record is not a valid break-glass path.
# A missing incident record is an evidence failure.
if [[ "$incident_record_required" == "true" && "$incident_record_present" == "false" ]]; then
  risk="BLOCKED"
  apply_allowed=false
  approval_required=false
  approval_level="none"
  reasons+=("incident_record_missing")
fi

# Non-blocked classification. This block implements precedence:
# BLOCKED > EMERGENCY > HIGH > MEDIUM > LOW > NO_CHANGE.
#
# EMERGENCY is next and remains EMERGENCY even if the plan contains destroy/replacement/IAM changes;
# Those are still recorded as reasons but do not change the emergency approval path.
if [[ "$risk" != "BLOCKED" ]]; then
  if [[ "$INCIDENT_MODE" == "true" ]]; then
    risk="EMERGENCY"
    approval_level="incident_commander_and_break_glass"
    reasons+=("incident_mode_enabled")
  elif [[ "$changed_count" -eq 0 ]]; then
    risk="NO_CHANGE"
    approval_required=false
    approval_level="none"
    reasons+=("no_managed_resource_changes")
  elif [[ "$TARGET_ENV" == "prod" ]]; then
    risk="HIGH"
    approval_level="senior_reviewer_or_prod_environment"
    reasons+=("target_env_prod")
  elif [[ "$TARGET_ENV" == "stage" ]]; then
    risk="MEDIUM"
    approval_level="reviewer_or_stage_environment"
    reasons+=("target_env_stage")
  fi

  if [[ "$destructive_count" -gt 0 ]]; then
    if [[ "$risk" != "EMERGENCY" ]]; then
      risk="HIGH"
      approval_required=true
      approval_level="senior_reviewer_or_high_risk_environment"
    fi
    reasons+=("destructive_change")
  fi

  if [[ "$replacement_count" -gt 0 ]]; then
    if [[ "$risk" != "EMERGENCY" ]]; then
      risk="HIGH"
      approval_required=true
      approval_level="senior_reviewer_or_high_risk_environment"
    fi
    reasons+=("replacement_change")
  fi

  if [[ "$iam_change_count" -gt 0 ]]; then
    if [[ "$risk" != "EMERGENCY" ]]; then
      risk="HIGH"
      approval_required=true
      approval_level="senior_reviewer_or_high_risk_environment"
    fi
    reasons+=("iam_change")
  fi

  if [[ "$asg_or_lt_change_count" -gt 0 && "$risk" == "LOW" ]]; then
    risk="MEDIUM"
    approval_level="reviewer_or_stage_environment"
    reasons+=("asg_or_launch_template_change")
  fi

  if [[ "$policy_warn_count" -gt 0 || "$cost_warn_count" -gt 0 ]]; then
    if [[ "$risk" == "LOW" || "$risk" == "NO_CHANGE" ]]; then
      risk="MEDIUM"
      approval_required=true
      approval_level="reviewer_or_stage_environment"
    fi
    reasons+=("warnings_present")
  fi
  fi

# If no special reason was recorded, this is the ordinary small dev change path.
if [[ "${#reasons[@]}" -eq 0 ]]; then
  reasons+=("small_dev_change")
fi

# Convert shell reason array into a JSON array. This becomes both `reasons` and
# `reason_codes` for compatibility/readability.
reasons_json="$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -s .)"

# Machine-readable decision artifact. CI and future automation should consume this file.
jq -n \
  --arg target_env "$TARGET_ENV" \
  --arg release_id "$RELEASE_ID" \
  --arg source_env "$SOURCE_ENV" \
  --arg risk "$risk" \
  --arg approval_level "$approval_level" \
  --argjson apply_allowed "$apply_allowed" \
  --argjson approval_required "$approval_required" \
  --argjson changed_count "$changed_count" \
  --argjson destructive_count "$destructive_count" \
  --argjson replacement_count "$replacement_count" \
  --argjson iam_change_count "$iam_change_count" \
  --argjson asg_or_lt_change_count "$asg_or_lt_change_count" \
  --argjson policy_deny_count "$policy_deny_count" \
  --argjson policy_warn_count "$policy_warn_count" \
  --argjson cost_deny_count "$cost_deny_count" \
  --argjson cost_warn_count "$cost_warn_count" \
  --argjson incident_mode "$INCIDENT_MODE" \
  --argjson incident_record_required "$incident_record_required" \
  --argjson incident_record_present "$incident_record_present" \
  --argjson promotion_required "$promotion_required" \
  --argjson promotion_present "$promotion_present" \
  --argjson promotion_valid "$promotion_valid" \
  --argjson reasons "$reasons_json" \
  '{
    target_env: $target_env,
    release_id: $release_id,
    source_env: $source_env,
    risk: $risk,
    approval_required: $approval_required,
    approval_level: $approval_level,
    approval: $approval_level,
    apply_allowed: $apply_allowed,
    changed_count: $changed_count,
    destructive_count: $destructive_count,
    replacement_count: $replacement_count,
    iam_change_count: $iam_change_count,
    asg_or_launch_template_change_count: $asg_or_lt_change_count,
    policy_deny_count: $policy_deny_count,
    policy_warn_count: $policy_warn_count,
    cost_deny_count: $cost_deny_count,
    cost_warn_count: $cost_warn_count,
    incident_mode: $incident_mode,
    incident_record_required: $incident_record_required,
    incident_record_present: $incident_record_present,
    promotion_required: $promotion_required,
    promotion_present: $promotion_present,
    promotion_valid: $promotion_valid,
    reasons: $reasons,
    reason_codes: $reasons,
    precedence: ["BLOCKED", "EMERGENCY", "HIGH", "MEDIUM", "LOW", "NO_CHANGE"],
    fail_closed: true
  }' > "$RISK_JSON"

# Human-readable decision artifact. This is what a reviewer can scan before approving an apply.
{
  echo "# Apply Risk Decision"
  echo
  echo "- Target environment: ${TARGET_ENV}"
  echo "- Release ID: ${RELEASE_ID:-n/a}"
  echo "- Source environment: ${SOURCE_ENV:-n/a}"
  echo "- Risk: ${risk}"
  echo "- Approval required: ${approval_required}"
  echo "- Approval level: ${approval_level}"
  echo "- Apply allowed: ${apply_allowed}"
  echo "- Changed resources: ${changed_count}"
  echo "- Destructive changes: ${destructive_count}"
  echo "- Replacement changes: ${replacement_count}"
  echo "- IAM changes: ${iam_change_count}"
  echo "- ASG/Launch Template changes: ${asg_or_lt_change_count}"
  echo "- Security policy denies: ${policy_deny_count}"
  echo "- Security policy warnings: ${policy_warn_count}"
  echo "- Cost policy denies: ${cost_deny_count}"
  echo "- Cost policy warnings: ${cost_warn_count}"
  echo "- Incident mode: ${INCIDENT_MODE}"
  echo "- Incident record required: ${incident_record_required}"
  echo "- Incident record present: ${incident_record_present}"
  echo "- Promotion required: ${promotion_required}"
  echo "- Promotion present: ${promotion_present}"
  echo "- Promotion valid: ${promotion_valid}"
  echo "- Fail closed: true"
  echo "- Precedence: BLOCKED > EMERGENCY > HIGH > MEDIUM > LOW > NO_CHANGE"
  echo
  echo "## Reason Codes"
  printf '%s\n' "${reasons[@]}" | sed 's/^/- /'
} > "$RISK_MD"

cat "$RISK_MD"

# Exit code 2 means the classifier successfully evaluated the inputs and decided the apply must not continue.
# Exit 0 means apply is allowed by the risk gate, not that a human approval is unnecessary.
if [[ "$apply_allowed" != "true" ]]; then
  exit 2
fi
