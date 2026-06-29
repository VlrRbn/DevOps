#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

usage() {
  cat >&2 <<'USAGE'
Usage:
  summarize-capstone.sh <evidence-dir>

Generates capstone-review-summary.md from available evidence files.
It does not modify infrastructure or Terraform state.
USAGE
}

EVIDENCE_DIR="${1:-}"
if [[ -z "$EVIDENCE_DIR" || ! -d "$EVIDENCE_DIR" ]]; then
  usage
  exit 64
fi

SUMMARY_MD="$EVIDENCE_DIR/capstone-review-summary.md"

read_file_or_na() {
  local file="$1"
  if [[ -s "$file" ]]; then
    tr '\n' ' ' < "$file" | sed 's/[[:space:]]\+/ /g; s/[[:space:]]$//'
  else
    printf 'n/a'
  fi
}

jq_value_or_na() {
  local file="$1"
  local filter="$2"
  if [[ -s "$file" ]] && command -v jq >/dev/null 2>&1; then
    jq -r "$filter // \"n/a\"" "$file" 2>/dev/null || printf 'n/a'
  else
    printf 'n/a'
  fi
}

target_env="$(read_file_or_na "$EVIDENCE_DIR/target-env.txt")"
release_id="$(read_file_or_na "$EVIDENCE_DIR/release-id.txt")"
git_sha="$(read_file_or_na "$EVIDENCE_DIR/git-sha.txt")"
git_status="$(read_file_or_na "$EVIDENCE_DIR/git-status.txt")"
post_apply_ec="$(read_file_or_na "$EVIDENCE_DIR/post_apply_exitcode.txt")"
risk_json="$EVIDENCE_DIR/risk-results/risk-decision.json"
if [[ ! -s "$risk_json" && -s "$EVIDENCE_DIR/risk-decision.json" ]]; then
  risk_json="$EVIDENCE_DIR/risk-decision.json"
fi

risk="$(jq_value_or_na "$risk_json" '.risk')"
apply_allowed="$(jq_value_or_na "$risk_json" '.apply_allowed')"
approval_level="$(jq_value_or_na "$risk_json" '.approval_level')"
reason_codes="$(jq_value_or_na "$risk_json" '(.reason_codes // []) | join(", ")')"

policy_decision="$(read_file_or_na "$EVIDENCE_DIR/policy-results/policy-decision.txt")"
if [[ "$policy_decision" == "n/a" ]]; then
  policy_decision="$(read_file_or_na "$EVIDENCE_DIR/policy-decision.txt")"
fi

cost_decision="$(read_file_or_na "$EVIDENCE_DIR/cost-policy-results/cost-decision.txt")"
if [[ "$cost_decision" == "n/a" ]]; then
  cost_decision="$(read_file_or_na "$EVIDENCE_DIR/cost-decision.txt")"
fi

runtime_summary="$EVIDENCE_DIR/runtime-health-summary.txt"
runtime_status="n/a"
if [[ -s "$runtime_summary" ]]; then
  runtime_status="$(awk -F= '$1 == "runtime_health_status" {print $2}' "$runtime_summary" | tail -1)"
  runtime_status="${runtime_status:-n/a}"
fi

final_decision="REVIEW_REQUIRED"
if [[ "$apply_allowed" == "false" || "$risk" == "BLOCKED" ]]; then
  final_decision="DO_NOT_APPLY"
elif [[ "$post_apply_ec" == "0" ]]; then
  final_decision="APPLIED_AND_CLEAN"
elif [[ "$post_apply_ec" == "2" ]]; then
  final_decision="APPLIED_WITH_DRIFT_OR_DIFF"
elif [[ "$apply_allowed" == "true" ]]; then
  final_decision="APPROVABLE_WITH_REVIEW"
fi

cat > "$SUMMARY_MD" <<SUMMARY
# Capstone Review Summary

- Commit SHA: ${git_sha}
- Git status: ${git_status}
- Target environment: ${target_env}
- Release ID: ${release_id}
- Security policy: ${policy_decision}
- Cost policy: ${cost_decision}
- Risk level: ${risk}
- Apply allowed by risk gate: ${apply_allowed}
- Approval level: ${approval_level}
- Reason codes: ${reason_codes}
- Post-apply drift exit code: ${post_apply_ec}
- Runtime health: ${runtime_status}
- Final decision: ${final_decision}

## Evidence Directory

\`\`\`text
${EVIDENCE_DIR}
\`\`\`

## Reviewer Notes

-
SUMMARY

echo "Summary written to: $SUMMARY_MD"
