#!/usr/bin/env bash
set -Eeuo pipefail

# Unit-style test runner for cost-policy.sh.
#
# These tests use small synthetic Terraform JSON plan fixtures from policies/tests.
# They do not call AWS or Terraform. The purpose is to lock the policy contract:
# - ALLOW exits 0 and writes COST_POLICY_DECISION=ALLOW.
# - DENY exits 2 and writes the expected rule to cost-deny.json.
# - WARN exits 0 and writes the expected rule to cost-warn.json.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="$SCRIPT_DIR/cost-policy.sh"
TEST_DIR="$SCRIPT_DIR/tests"
TMP_ROOT="${TMPDIR:-/tmp}/l75-cost-policy-tests_$$"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Positive case: policy should allow the plan and produce a decision file.
allow_case() {
  local name="$1"
  local plan="$2"
  local env="$3"
  local out_dir="$TMP_ROOT/$name"
  mkdir -p "$out_dir"
  OUT_DIR="$out_dir" "$POLICY" "$plan" "$env" >"$TMP_ROOT/${name}.log"
  grep -q 'COST_POLICY_DECISION=ALLOW' "$out_dir/cost-decision.txt"
}

# Negative policy case: policy evaluated successfully and blocked the plan.
# Exit code 2 is expected here; any other code means either fail-open or tooling failure.
deny_case() {
  local name="$1"
  local plan="$2"
  local env="$3"
  local expected_rule="$4"
  local out_dir="$TMP_ROOT/$name"
  mkdir -p "$out_dir"
  set +e
  OUT_DIR="$out_dir" "$POLICY" "$plan" "$env" >"$TMP_ROOT/${name}.log" 2>&1
  local ec=$?
  set -e
  if [[ "$ec" -ne 2 ]]; then
    echo "Expected DENY exit code 2 for $name, got $ec" >&2
    cat "$TMP_ROOT/${name}.log" >&2
    exit 1
  fi
  grep -q 'COST_POLICY_DECISION=DENY' "$out_dir/cost-decision.txt"
  jq -e --arg rule "$expected_rule" 'any(.[]; .rule == $rule)' "$out_dir/cost-deny.json" >/dev/null
}

# Warning case: policy should allow the plan but emit a review signal. This is
# how cost/blast-radius warnings flow into risk-classifier.sh.
warn_case() {
  local name="$1"
  local plan="$2"
  local env="$3"
  local expected_rule="$4"
  local out_dir="$TMP_ROOT/$name"
  mkdir -p "$out_dir"
  OUT_DIR="$out_dir" "$POLICY" "$plan" "$env" >"$TMP_ROOT/${name}.log"
  grep -q 'COST_POLICY_DECISION=ALLOW' "$out_dir/cost-decision.txt"
  jq -e --arg rule "$expected_rule" 'any(.[]; .rule == $rule)' "$out_dir/cost-warn.json" >/dev/null
}

# Usage/input cases must not be confused with DENY. They prove invalid envs and
# missing files fail with their documented exit codes.
usage_error_case() {
  local name="$1"
  local expected_exit="$2"
  shift 2
  set +e
  "$POLICY" "$@" >"$TMP_ROOT/${name}.log" 2>&1
  local ec=$?
  set -e
  if [[ "$ec" -ne "$expected_exit" ]]; then
    echo "Expected exit code $expected_exit for $name, got $ec" >&2
    cat "$TMP_ROOT/${name}.log" >&2
    exit 1
  fi
}

# Baseline: normal dev plan should pass.
allow_case safe_dev "$TEST_DIR/cost-safe-plan.json" dev

# NAT is denied in dev because this lesson keeps dev cheap by default.
deny_case nat_dev "$TEST_DIR/cost-nat-plan.json" dev nat_gateway_cost_signal

# NAT is only warned in stage/prod because the design may be valid there.
warn_case nat_stage "$TEST_DIR/cost-nat-plan.json" stage nat_gateway_cost_signal

# ASG capacity above the environment limit is a hard stop.
deny_case high_asg_dev "$TEST_DIR/cost-high-asg-plan.json" dev deny_asg_max_size_above_env_limit
deny_case high_asg_prod "$TEST_DIR/cost-high-asg-plan.json" prod deny_asg_max_size_above_env_limit

# Large instance shapes are denied regardless of environment in this lab.
deny_case large_instance "$TEST_DIR/cost-large-instance-plan.json" stage deny_large_instance_type

# Public load balancer is a warning, not a deny, because public exposure can be
# intentional.
warn_case public_lb "$TEST_DIR/cost-public-lb-plan.json" prod warn_public_load_balancer_blast_radius

# Input validation guardrails.
usage_error_case invalid_env 64 "$TEST_DIR/cost-safe-plan.json" qa
usage_error_case missing_plan 1 "$TEST_DIR/does-not-exist.json" dev

echo "cost policy tests passed"
