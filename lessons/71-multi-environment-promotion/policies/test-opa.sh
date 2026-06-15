#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_DIR="$SCRIPT_DIR/opa"
TEST_DIR="$SCRIPT_DIR/tests"

# This runner checks the Rego file against the same core fixtures as the jq policy.

if ! command -v opa >/dev/null 2>&1; then
  echo "opa is required for optional Rego policy tests" >&2
  exit 1
fi

opa check "$POLICY_DIR/terraform.rego"
opa fmt --diff "$POLICY_DIR/terraform.rego"

expect_deny_count() {
  local name="$1"
  local plan="$2"
  local expected="$3"
  local actual

  actual="$(opa eval -f raw -d "$POLICY_DIR/terraform.rego" -i "$plan" 'count(data.terraform.plan.deny)')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected OPA deny count for $name: expected=$expected actual=$actual" >&2
    opa eval -f pretty -d "$POLICY_DIR/terraform.rego" -i "$plan" 'data.terraform.plan.deny' >&2
    exit 1
  fi
}

expect_deny_count safe "$TEST_DIR/safe-plan.json" 0
expect_deny_count warn_only "$TEST_DIR/warn-plan.json" 0
expect_deny_count no_op_warn "$TEST_DIR/no-op-warn-plan.json" 0
expect_deny_count public_egress "$TEST_DIR/public-egress-plan.json" 0
expect_deny_count destroy "$TEST_DIR/destroy-plan.json" 1
expect_deny_count replacement "$TEST_DIR/replacement-plan.json" 1
expect_deny_count public_ingress "$TEST_DIR/public-ingress-plan.json" 1
expect_deny_count public_ingress_inline_sg "$TEST_DIR/public-ingress-inline-sg-plan.json" 1
expect_deny_count missing_tags "$TEST_DIR/missing-tags-plan.json" 2
expect_deny_count empty_tags "$TEST_DIR/empty-tags-plan.json" 1

echo "opa policy tests passed"
