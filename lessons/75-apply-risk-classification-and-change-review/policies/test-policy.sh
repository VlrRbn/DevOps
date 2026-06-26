#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="$SCRIPT_DIR/terraform-plan-policy.sh"
TEST_DIR="$SCRIPT_DIR/tests"
TMP_ROOT="${TMPDIR:-/tmp}/l74-policy-tests_$$"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

# These fixtures are intentionally small synthetic Terraform JSON plans.
# They keep policy behavior testable without an AWS account or provider initialization.

pass_case() {
  local name="$1"
  local plan="$2"
  local out_dir="$TMP_ROOT/$name"
  mkdir -p "$out_dir"
  OUT_DIR="$out_dir" "$POLICY" "$plan" >"/tmp/l74-policy-${name}.log"
  grep -q 'POLICY_DECISION=ALLOW' "$out_dir/policy-decision.txt"
}

pass_case_no_warnings() {
  local name="$1"
  local plan="$2"
  local out_dir="$TMP_ROOT/$name"
  mkdir -p "$out_dir"
  OUT_DIR="$out_dir" "$POLICY" "$plan" >"/tmp/l74-policy-${name}.log"
  grep -q 'POLICY_DECISION=ALLOW' "$out_dir/policy-decision.txt"
  jq -e 'length == 0' "$out_dir/policy-warn.json" >/dev/null
}

deny_case() {
  local name="$1"
  local plan="$2"
  local expected_rule="$3"
  local out_dir="$TMP_ROOT/$name"
  mkdir -p "$out_dir"
  set +e
  OUT_DIR="$out_dir" "$POLICY" "$plan" >"/tmp/l74-policy-${name}.log" 2>&1
  local ec=$?
  set -e
  if [[ "$ec" -ne 2 ]]; then
    echo "Expected DENY exit code 2 for $name, got $ec" >&2
    cat "/tmp/l74-policy-${name}.log" >&2
    exit 1
  fi
  grep -q 'POLICY_DECISION=DENY' "$out_dir/policy-decision.txt"
  jq -e --arg rule "$expected_rule" 'any(.[]; .rule == $rule)' "$out_dir/policy-deny.json" >/dev/null
}

pass_case_with_exception() {
  local name="$1"
  local plan="$2"
  local exception="$3"
  local out_dir="$TMP_ROOT/$name"
  mkdir -p "$out_dir"
  ALLOW_DESTROY_FILE="$exception" OUT_DIR="$out_dir" "$POLICY" "$plan" >"/tmp/l74-policy-${name}.log"
  grep -q 'POLICY_DECISION=ALLOW' "$out_dir/policy-decision.txt"
  # A valid exception removes only approved destructive addresses from the effective deny list.
  jq -e 'length == 0' "$out_dir/policy-deny.json" >/dev/null
}

deny_case_with_exception() {
  local name="$1"
  local plan="$2"
  local exception="$3"
  local expected_rule="$4"
  local out_dir="$TMP_ROOT/$name"
  mkdir -p "$out_dir"
  set +e
  ALLOW_DESTROY_FILE="$exception" OUT_DIR="$out_dir" "$POLICY" "$plan" >"/tmp/l74-policy-${name}.log" 2>&1
  local ec=$?
  set -e
  if [[ "$ec" -ne 2 ]]; then
    echo "Expected DENY exit code 2 for $name, got $ec" >&2
    cat "/tmp/l74-policy-${name}.log" >&2
    exit 1
  fi
  grep -q 'POLICY_DECISION=DENY' "$out_dir/policy-decision.txt"
  jq -e --arg rule "$expected_rule" 'any(.[]; .rule == $rule)' "$out_dir/policy-deny.json" >/dev/null
}

input_error_case() {
  local name="$1"
  local plan="$2"
  local exception="$3"
  local out_dir="$TMP_ROOT/$name"
  mkdir -p "$out_dir"
  set +e
  ALLOW_DESTROY_FILE="$exception" OUT_DIR="$out_dir" "$POLICY" "$plan" >"/tmp/l74-policy-${name}.log" 2>&1
  local ec=$?
  set -e
  if [[ "$ec" -ne 1 ]]; then
    echo "Expected input error exit code 1 for $name, got $ec" >&2
    cat "/tmp/l74-policy-${name}.log" >&2
    exit 1
  fi
}

pass_case safe "$TEST_DIR/safe-plan.json"
pass_case warn_only "$TEST_DIR/warn-plan.json"
pass_case_no_warnings no_op_warn "$TEST_DIR/no-op-warn-plan.json"
pass_case public_egress "$TEST_DIR/public-egress-plan.json"
deny_case destroy "$TEST_DIR/destroy-plan.json" deny_destructive_change
deny_case replacement "$TEST_DIR/replacement-plan.json" deny_destructive_change
deny_case public_ingress "$TEST_DIR/public-ingress-plan.json" deny_public_ingress
deny_case public_ingress_inline_sg "$TEST_DIR/public-ingress-inline-sg-plan.json" deny_public_ingress_inline_sg
deny_case missing_tags "$TEST_DIR/missing-tags-plan.json" deny_missing_required_tags
deny_case empty_tags "$TEST_DIR/empty-tags-plan.json" deny_missing_required_tags
pass_case_with_exception destroy_allowed "$TEST_DIR/destroy-plan.json" "$SCRIPT_DIR/allow-destroy.example.json"
deny_case_with_exception destroy_wrong_exception "$TEST_DIR/destroy-plan.json" "$TEST_DIR/allow-destroy-wrong-address.json" deny_destructive_change
input_error_case invalid_wildcard_exception "$TEST_DIR/destroy-plan.json" "$TEST_DIR/allow-destroy-invalid-wildcard.json"
input_error_case expired_exception "$TEST_DIR/destroy-plan.json" "$TEST_DIR/allow-destroy-expired.json"

echo "policy tests passed"
