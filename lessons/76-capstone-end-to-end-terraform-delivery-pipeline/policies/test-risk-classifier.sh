#!/usr/bin/env bash
set -Eeuo pipefail

# Unit-style test runner for risk-classifier.sh.
#
# This test suite is intentionally broader than simple happy-path checks. The
# classifier is a final gate before apply, so the tests cover fail-open risks:
# missing policy outputs, invalid JSON, missing/invalid promotion evidence,
# incident mode without evidence, and CI escape hatches.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/tests"
RISK_POLICY="$SCRIPT_DIR/risk-classifier.sh"
SECURITY_POLICY="$SCRIPT_DIR/security-policy.sh"
COST_POLICY="$SCRIPT_DIR/cost-policy.sh"
TMP_ROOT="${TMPDIR:-/tmp}/l76-risk-classifier-tests_$$"

# Every test writes isolated artifacts under /tmp so repository files are not
# polluted and tests can inspect each case independently.
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT"

# Most classifier tests need a clean policy ALLOW state. These helpers create the
# exact files risk-classifier.sh expects from lower-level policy stages.
write_empty_policy_outputs() {
  local dir="$1"
  mkdir -p "$dir"
  echo '[]' > "$dir/policy-deny.json"
  echo '[]' > "$dir/policy-warn.json"
}

# Same idea for cost policy outputs: an empty JSON array means no deny/warn.
write_empty_cost_outputs() {
  local dir="$1"
  mkdir -p "$dir"
  echo '[]' > "$dir/cost-deny.json"
  echo '[]' > "$dir/cost-warn.json"
}

# Assert the two most important fields for every case: final risk and whether the
# risk gate allows apply. Detailed cases add jq assertions below.
assert_risk() {
  local name="$1"
  local expected_risk="$2"
  local expected_allowed="$3"
  local out_dir="$TMP_ROOT/$name/risk"
  jq -e --arg risk "$expected_risk" --argjson allowed "$expected_allowed" \
    '.risk == $risk and .apply_allowed == $allowed' \
    "$out_dir/risk-decision.json" >/dev/null
}

# Assert that a specific reason code is present. Reason codes are the contract
# reviewers and automation use to understand why the classifier decided something.
assert_reason() {
  local name="$1"
  local expected_reason="$2"
  local out_dir="$TMP_ROOT/$name/risk"
  jq -e --arg reason "$expected_reason" \
    '.reason_codes | index($reason)' \
    "$out_dir/risk-decision.json" >/dev/null
}

# Generic classifier runner for normal cases.
#
# It creates empty policy/cost outputs, runs the classifier with optional extra
# env vars, and asserts the expected exit code. This keeps individual test cases
# compact while still preserving stdout/stderr artifacts for debugging failures.
run_classifier() {
  local name="$1"
  local plan="$2"
  local env_name="$3"
  local expected_exit="$4"
  shift 4

  local case_dir="$TMP_ROOT/$name"
  local policy_dir="$case_dir/policy"
  local cost_dir="$case_dir/cost"
  local risk_dir="$case_dir/risk"

  write_empty_policy_outputs "$policy_dir"
  write_empty_cost_outputs "$cost_dir"

  set +e
  POLICY_DIR="$policy_dir" COST_DIR="$cost_dir" OUT_DIR="$risk_dir" "$@" \
    "$RISK_POLICY" "$plan" "$env_name" > "$case_dir/stdout.txt" 2> "$case_dir/stderr.txt"
  local ec=$?
  set -e

  if [[ "$ec" -ne "$expected_exit" ]]; then
    echo "Unexpected exit for $name: expected=$expected_exit actual=$ec" >&2
    cat "$case_dir/stdout.txt" >&2 || true
    cat "$case_dir/stderr.txt" >&2 || true
    exit 1
  fi
}

# Runner for fail-closed cases where policy/cost outputs intentionally do not
# exist. The expected behavior is BLOCKED, not LOW/NO_CHANGE.
run_classifier_with_missing_outputs() {
  local name="$1"
  local plan="$2"
  local env_name="$3"
  local expected_exit="$4"
  shift 4

  local case_dir="$TMP_ROOT/$name"
  local policy_dir="$case_dir/policy"
  local cost_dir="$case_dir/cost"
  local risk_dir="$case_dir/risk"

  mkdir -p "$policy_dir" "$cost_dir"

  set +e
  POLICY_DIR="$policy_dir" COST_DIR="$cost_dir" OUT_DIR="$risk_dir" "$@" \
    "$RISK_POLICY" "$plan" "$env_name" > "$case_dir/stdout.txt" 2> "$case_dir/stderr.txt"
  local ec=$?
  set -e

  if [[ "$ec" -ne "$expected_exit" ]]; then
    echo "Unexpected exit for $name: expected=$expected_exit actual=$ec" >&2
    cat "$case_dir/stdout.txt" >&2 || true
    cat "$case_dir/stderr.txt" >&2 || true
    exit 1
  fi
}

# Runner for malformed lower-level policy output. A policy output that is not a
# JSON array must block classification because the classifier cannot know whether
# denies were lost.
run_classifier_with_invalid_policy_json() {
  local name="$1"
  local plan="$2"
  local env_name="$3"
  local expected_exit="$4"
  shift 4

  local case_dir="$TMP_ROOT/$name"
  local policy_dir="$case_dir/policy"
  local cost_dir="$case_dir/cost"
  local risk_dir="$case_dir/risk"

  mkdir -p "$policy_dir" "$cost_dir"
  echo '{}' > "$policy_dir/policy-deny.json"
  echo '[]' > "$policy_dir/policy-warn.json"
  echo '[]' > "$cost_dir/cost-deny.json"
  echo '[]' > "$cost_dir/cost-warn.json"

  set +e
  POLICY_DIR="$policy_dir" COST_DIR="$cost_dir" OUT_DIR="$risk_dir" "$@" \
    "$RISK_POLICY" "$plan" "$env_name" > "$case_dir/stdout.txt" 2> "$case_dir/stderr.txt"
  local ec=$?
  set -e

  if [[ "$ec" -ne "$expected_exit" ]]; then
    echo "Unexpected exit for $name: expected=$expected_exit actual=$ec" >&2
    cat "$case_dir/stdout.txt" >&2 || true
    cat "$case_dir/stderr.txt" >&2 || true
    exit 1
  fi
}

# Runner that executes the real security and cost policy scripts before the risk
# classifier. This tests integration behavior, not just hand-written empty arrays.
# The lower-level scripts can exit 2 for DENY, so they are run with `|| true` and
# the risk classifier consumes their output artifacts.
run_policy_classifier() {
  local name="$1"
  local plan="$2"
  local env_name="$3"
  local expected_exit="$4"
  shift 4

  local case_dir="$TMP_ROOT/$name"
  local policy_dir="$case_dir/policy"
  local cost_dir="$case_dir/cost"
  local risk_dir="$case_dir/risk"

  mkdir -p "$policy_dir" "$cost_dir"
  OUT_DIR="$policy_dir" "$SECURITY_POLICY" "$plan" > "$case_dir/security-policy.txt" 2>&1 || true
  OUT_DIR="$cost_dir" "$COST_POLICY" "$plan" "$env_name" > "$case_dir/cost-policy.txt" 2>&1 || true

  set +e
  POLICY_DIR="$policy_dir" COST_DIR="$cost_dir" OUT_DIR="$risk_dir" "$@" \
    "$RISK_POLICY" "$plan" "$env_name" > "$case_dir/stdout.txt" 2> "$case_dir/stderr.txt"
  local ec=$?
  set -e

  if [[ "$ec" -ne "$expected_exit" ]]; then
    echo "Unexpected exit for $name: expected=$expected_exit actual=$ec" >&2
    cat "$case_dir/stdout.txt" >&2 || true
    cat "$case_dir/stderr.txt" >&2 || true
    exit 1
  fi
}

# Valid dev->stage promotion evidence.
promotion_file="$TMP_ROOT/promotion-evidence.json"
cat > "$promotion_file" <<'EOF'
{
  "release_id": "l76-demo",
  "source_env": "dev",
  "status": "passed",
  "commit_sha": "0123456789abcdef0123456789abcdef01234567",
  "source_workflow_run_url": "https://github.com/VlrRbn/DevOps/actions/runs/760001"
}
EOF

# Valid stage->prod promotion evidence.
prod_promotion_file="$TMP_ROOT/prod-promotion-evidence.json"
cat > "$prod_promotion_file" <<'EOF'
{
  "release_id": "l76-demo",
  "source_env": "stage",
  "status": "passed",
  "commit_sha": "0123456789abcdef0123456789abcdef01234567",
  "source_workflow_run_url": "https://github.com/VlrRbn/DevOps/actions/runs/760002"
}
EOF

# Invalid evidence used to prove mismatches and failed status block stage/prod.
invalid_promotion_file="$TMP_ROOT/invalid-promotion-evidence.json"
cat > "$invalid_promotion_file" <<'EOF'
{
  "release_id": "wrong-release",
  "source_env": "dev",
  "status": "failed",
  "commit_sha": "not-a-sha",
  "source_workflow_run_url": "not-a-url"
}
EOF

# Invalid plan-shape fixtures. These prove arbitrary JSON cannot become
# NO_CHANGE/apply_allowed=true.
not_a_plan_file="$TMP_ROOT/not-a-plan.json"
echo '{}' > "$not_a_plan_file"

malformed_plan_file="$TMP_ROOT/malformed-plan.json"
cat > "$malformed_plan_file" <<'EOF'
{
  "resource_changes": [
    {
      "mode": "managed",
      "type": "aws_instance"
    }
  ]
}
EOF

# Minimal incident record used for EMERGENCY positive cases.
incident_record="$TMP_ROOT/incident-record.md"
cat > "$incident_record" <<'EOF'
# Incident Record

- Incident ID: INC-L76-001
- Severity: SEV-2
- Reason: risk classifier emergency-mode test
- Approval: simulated
EOF

# Baseline LOW: dev change, no policy/cost findings, no promotion required.
run_classifier low_dev "$TEST_DIR/safe-plan.json" dev 0 env REQUIRE_PROMOTION_EVIDENCE=false
assert_risk low_dev LOW true
jq -e '.approval_required == true and .approval_level == "standard" and .approval == "standard"' \
  "$TMP_ROOT/low_dev/risk/risk-decision.json" >/dev/null
assert_reason low_dev small_dev_change

# NO_CHANGE: valid plan with only no-op managed resources should be allowed
# without approval, but only after lower-level policy outputs exist and are valid.
run_classifier no_change "$TEST_DIR/no-op-warn-plan.json" dev 0 env REQUIRE_PROMOTION_EVIDENCE=false
assert_risk no_change NO_CHANGE true
jq -e '.approval_required == false and .approval_level == "none"' \
  "$TMP_ROOT/no_change/risk/risk-decision.json" >/dev/null
assert_reason no_change no_managed_resource_changes

# NO_CHANGE in prod does not require promotion evidence because there is nothing
# to promote. This prevents "empty plan" runs from being blocked unnecessarily.
run_classifier no_change_prod_without_promotion "$TEST_DIR/no-op-warn-plan.json" prod 0 env
assert_risk no_change_prod_without_promotion NO_CHANGE true
jq -e '.promotion_required == false and .approval_required == false and .approval_level == "none"' \
  "$TMP_ROOT/no_change_prod_without_promotion/risk/risk-decision.json" >/dev/null
assert_reason no_change_prod_without_promotion no_managed_resource_changes

# Same no-change behavior in CI with promotion disabled is allowed because
# changed_count is zero.
run_classifier no_change_prod_ci_without_promotion "$TEST_DIR/no-op-warn-plan.json" prod 0 \
  env GITHUB_ACTIONS=true REQUIRE_PROMOTION_EVIDENCE=false
assert_risk no_change_prod_ci_without_promotion NO_CHANGE true

# MEDIUM: stage change with real cost warning and valid dev->stage evidence.
run_policy_classifier medium_stage_nat "$TEST_DIR/cost-nat-plan.json" stage 0 \
  env PROMOTION_EVIDENCE_FILE="$promotion_file" RELEASE_ID=l76-demo SOURCE_ENV=dev
assert_risk medium_stage_nat MEDIUM true
jq -e '.promotion_present == true and .promotion_valid == true' \
  "$TMP_ROOT/medium_stage_nat/risk/risk-decision.json" >/dev/null

# HIGH: prod change with valid stage->prod evidence.
run_classifier high_prod "$TEST_DIR/safe-plan.json" prod 0 \
  env PROMOTION_EVIDENCE_FILE="$prod_promotion_file" RELEASE_ID=l76-demo SOURCE_ENV=stage
assert_risk high_prod HIGH true
jq -e '.promotion_present == true and .promotion_valid == true' \
  "$TMP_ROOT/high_prod/risk/risk-decision.json" >/dev/null

# Invalid promotion evidence must block stage/prod even if the file exists.
run_classifier invalid_promotion_evidence "$TEST_DIR/safe-plan.json" stage 2 \
  env PROMOTION_EVIDENCE_FILE="$invalid_promotion_file" RELEASE_ID=l76-demo SOURCE_ENV=dev
assert_risk invalid_promotion_evidence BLOCKED false
assert_reason invalid_promotion_evidence promotion_evidence_release_id_mismatch
assert_reason invalid_promotion_evidence promotion_evidence_status_not_passed
assert_reason invalid_promotion_evidence promotion_evidence_commit_sha_invalid
assert_reason invalid_promotion_evidence promotion_evidence_source_workflow_run_url_invalid

# Lower-level policy DENY must become BLOCKED at the risk layer.
run_policy_classifier blocked_public_ingress "$TEST_DIR/public-ingress-plan.json" dev 2 env REQUIRE_PROMOTION_EVIDENCE=false
assert_risk blocked_public_ingress BLOCKED false
assert_reason blocked_public_ingress policy_or_cost_deny_present

# Missing lower-level outputs are a fail-closed case. This prevents "policy did
# not run" from looking like "policy allowed".
run_classifier_with_missing_outputs fail_closed_missing_outputs "$TEST_DIR/safe-plan.json" dev 2 \
  env REQUIRE_PROMOTION_EVIDENCE=false
assert_risk fail_closed_missing_outputs BLOCKED false
assert_reason fail_closed_missing_outputs policy_deny_missing
assert_reason fail_closed_missing_outputs policy_warn_missing
assert_reason fail_closed_missing_outputs cost_deny_missing
assert_reason fail_closed_missing_outputs cost_warn_missing

# Malformed lower-level output is also fail-closed.
run_classifier_with_invalid_policy_json invalid_policy_json "$TEST_DIR/safe-plan.json" dev 2 \
  env REQUIRE_PROMOTION_EVIDENCE=false
assert_risk invalid_policy_json BLOCKED false
assert_reason invalid_policy_json policy_deny_invalid_json_array

# EMERGENCY positive path requires incident evidence and uses a different approval
# level. It is not just HIGH with another name.
run_classifier emergency_dev "$TEST_DIR/safe-plan.json" dev 0 \
  env INCIDENT_MODE=true INCIDENT_RECORD_FILE="$incident_record" REQUIRE_PROMOTION_EVIDENCE=false
assert_risk emergency_dev EMERGENCY true
jq -e '.approval_required == true and .approval_level == "incident_commander_and_break_glass"' \
  "$TMP_ROOT/emergency_dev/risk/risk-decision.json" >/dev/null

# EMERGENCY without an incident record is blocked.
run_classifier missing_incident_record "$TEST_DIR/safe-plan.json" dev 2 \
  env INCIDENT_MODE=true REQUIRE_PROMOTION_EVIDENCE=false
assert_risk missing_incident_record BLOCKED false
assert_reason missing_incident_record incident_record_missing

# EMERGENCY can include destructive changes, but only with incident evidence. The
# classifier records destructive reasons while keeping the emergency approval path.
run_classifier emergency_destroy "$TEST_DIR/destroy-plan.json" prod 0 \
  env INCIDENT_MODE=true INCIDENT_RECORD_FILE="$incident_record" REQUIRE_PROMOTION_EVIDENCE=false
assert_risk emergency_destroy EMERGENCY true

# Stage/prod managed changes require promotion evidence by default.
run_classifier missing_stage_promotion "$TEST_DIR/safe-plan.json" stage 2 env RELEASE_ID=l76-demo SOURCE_ENV=dev
assert_risk missing_stage_promotion BLOCKED false

# Input validation cases.
run_classifier invalid_env "$TEST_DIR/safe-plan.json" qa 64 env REQUIRE_PROMOTION_EVIDENCE=false

run_classifier invalid_plan_shape "$not_a_plan_file" dev 64 env REQUIRE_PROMOTION_EVIDENCE=false

run_classifier malformed_plan_shape "$malformed_plan_file" dev 64 env REQUIRE_PROMOTION_EVIDENCE=false

# CI bypass guards. These are defensive tests for dangerous escape hatches that
# are acceptable locally but must not be usable in GitHub Actions.
run_classifier ci_disallows_missing_policy_escape_hatch "$TEST_DIR/safe-plan.json" dev 64 \
  env GITHUB_ACTIONS=true ALLOW_MISSING_POLICY_OUTPUTS=true REQUIRE_PROMOTION_EVIDENCE=false

run_classifier ci_disallows_stage_promotion_bypass "$TEST_DIR/safe-plan.json" stage 64 \
  env GITHUB_ACTIONS=true REQUIRE_PROMOTION_EVIDENCE=false

printf 'risk classifier tests passed\n'
