#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="$SCRIPT_DIR/cost-policy.sh"
TEST_DIR="$SCRIPT_DIR/tests"
TMP_ROOT="${TMPDIR:-/tmp}/l73-cost-policy-tests_$$"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

allow_case() {
  local name="$1"
  local plan="$2"
  local env="$3"
  local out_dir="$TMP_ROOT/$name"
  mkdir -p "$out_dir"
  OUT_DIR="$out_dir" "$POLICY" "$plan" "$env" >"$TMP_ROOT/${name}.log"
  grep -q 'COST_POLICY_DECISION=ALLOW' "$out_dir/cost-decision.txt"
}

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

allow_case safe_dev "$TEST_DIR/cost-safe-plan.json" dev
deny_case nat_dev "$TEST_DIR/cost-nat-plan.json" dev nat_gateway_cost_signal
warn_case nat_stage "$TEST_DIR/cost-nat-plan.json" stage nat_gateway_cost_signal
deny_case high_asg_dev "$TEST_DIR/cost-high-asg-plan.json" dev deny_asg_max_size_above_env_limit
deny_case high_asg_prod "$TEST_DIR/cost-high-asg-plan.json" prod deny_asg_max_size_above_env_limit
deny_case large_instance "$TEST_DIR/cost-large-instance-plan.json" stage deny_large_instance_type
warn_case public_lb "$TEST_DIR/cost-public-lb-plan.json" prod warn_public_load_balancer_blast_radius
usage_error_case invalid_env 64 "$TEST_DIR/cost-safe-plan.json" qa
usage_error_case missing_plan 1 "$TEST_DIR/does-not-exist.json" dev

echo "cost policy tests passed"
