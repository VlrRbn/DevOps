#!/usr/bin/env bash
set -Eeuo pipefail

# Cost/blast-radius policy for synthetic Terraform JSON plans.
#
# This script is intentionally small and local-only: it does not call AWS,
# Infracost, Terraform, or provider APIs. It reads an already generated
# `terraform show -json` plan and produces two machine-readable files:
#
# - cost-deny.json: findings that must stop apply.
# - cost-warn.json: findings that should be reviewed but do not stop apply.
#
# The risk classifier consumes these files later. That is why the script keeps
# DENY and WARN separate instead of printing only a human-readable summary.
usage() {
  cat >&2 <<'USAGE'
Usage:
  cost-policy.sh <tfplan.json> <target_env>

Environment variables:
  OUT_DIR             Output directory. Default: current directory.

Manual example:
  OUT_DIR=/tmp/l75-cost cost-policy.sh tfplan.json dev

Exit codes:
  0 - allowed, possibly with warnings
  1 - input/tooling error
  2 - denied by cost/blast-radius policy
 64 - usage/input shape error
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

PLAN_JSON="${1:-}"
TARGET_ENV="${2:-}"
OUT_DIR="${OUT_DIR:-.}"

# Require both inputs explicitly. A missing target environment would make the
# cost limits ambiguous, so this is treated as usage error instead of defaulting.
if [[ -z "$PLAN_JSON" || -z "$TARGET_ENV" ]]; then
  usage
  exit 64
fi

# jq is the only parser used here. The script relies on Terraform JSON plan structure.
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for cost policy checks" >&2
  exit 1
fi

# A missing plan is a tooling/input error, not a policy DENY. Exit 1 keeps this
# distinct from exit 2, which means "policy evaluated and blocked the change".
if [[ ! -f "$PLAN_JSON" ]]; then
  echo "PLAN_JSON not found: $PLAN_JSON" >&2
  exit 1
fi

# Environment-specific thresholds are the core of this lesson:
#
# - dev is strict and cheap: small ASG limit, NAT Gateway denied.
# - stage/prod can have more capacity, NAT is a warning because it may be valid.
#
# This keeps the policy deterministic while still showing how blast-radius
# controls can vary by environment.
case "$TARGET_ENV" in
  dev)
    MAX_ASG_MAX_SIZE=2
    NAT_MODE="deny"
    ;;
  stage)
    MAX_ASG_MAX_SIZE=3
    NAT_MODE="warn"
    ;;
  prod)
    MAX_ASG_MAX_SIZE=4
    NAT_MODE="warn"
    ;;
  *)
    echo "target_env must be one of: dev, stage, prod" >&2
    exit 64
    ;;
esac

mkdir -p "$OUT_DIR"

# Output contract consumed by risk-classifier.sh and CI artifacts.
DENY_OUT="$OUT_DIR/cost-deny.json"
WARN_OUT="$OUT_DIR/cost-warn.json"
DECISION_OUT="$OUT_DIR/cost-decision.txt"

# DENY: ASG max_size above the environment budget.
#
# Deletes are ignored because removing capacity does not increase cost/blast
# radius. Creates and updates are checked against the target environment limit.
jq --argjson max "$MAX_ASG_MAX_SIZE" '
[
  .resource_changes[]?
  | select(.mode == "managed")
  | select(.type == "aws_autoscaling_group")
  | select((.change.actions | index("delete")) | not)
  | select((.change.after.max_size // 0) > $max)
  | {
      rule: "deny_asg_max_size_above_env_limit",
      address: .address,
      max_size: .change.after.max_size,
      env_limit: $max
    }
]
' "$PLAN_JSON" > "$OUT_DIR/asg-max-deny.json"

# DENY or WARN: NAT Gateway usage.
#
# In dev this lesson blocks them completely. In stage/prod it only warns so the
# reviewer can decide whether the design justifies the cost.
jq '
[
  .resource_changes[]?
  | select(.mode == "managed")
  | select(.type == "aws_nat_gateway")
  | select((.change.actions | index("delete")) | not)
  | {
      rule: "nat_gateway_cost_signal",
      address: .address,
      actions: .change.actions
    }
]
' "$PLAN_JSON" > "$OUT_DIR/nat-signal.json"

# Convert the shared NAT signal into either deny or warning output based on the
# target environment selected above.
if [[ "$NAT_MODE" == "deny" ]]; then
  cp "$OUT_DIR/nat-signal.json" "$OUT_DIR/nat-deny.json"
  echo '[]' > "$OUT_DIR/nat-warn.json"
else
  echo '[]' > "$OUT_DIR/nat-deny.json"
  cp "$OUT_DIR/nat-signal.json" "$OUT_DIR/nat-warn.json"
fi

# DENY: large instance shapes.
#
# This is a simple pattern-based guardrail. It does not try to price every
# instance type; it blocks obviously expensive shapes such as 2xlarge+ and metal.
jq '
[
  .resource_changes[]?
  | select(.mode == "managed")
  | select(.type == "aws_launch_template" or .type == "aws_instance")
  | select((.change.actions | index("delete")) | not)
  | (.change.after.instance_type // "") as $instance_type
  | select($instance_type | test("^[a-z][a-z0-9]*[0-9][a-z0-9.]*\\.(2xlarge|4xlarge|8xlarge|12xlarge|16xlarge|24xlarge|32xlarge|metal)$"))
  | {
      rule: "deny_large_instance_type",
      address: .address,
      instance_type: $instance_type
    }
]
' "$PLAN_JSON" > "$OUT_DIR/large-instance-deny.json"

# WARN: public load balancers.
#
# Public ALBs/NLBs can be valid, but they expand external exposure and review
# scope. The policy warns instead of denying because the correct decision depends
# on architecture.
jq '
[
  .resource_changes[]?
  | select(.mode == "managed")
  | select(.type == "aws_lb")
  | select((.change.actions | index("delete")) | not)
  | (.change.after // {}) as $after
  | select((if ($after | has("internal")) then $after.internal else true end) == false)
  | {
      rule: "warn_public_load_balancer_blast_radius",
      address: .address,
      name: ($after.name // null)
    }
]
' "$PLAN_JSON" > "$OUT_DIR/public-lb-warn.json"

# Merge all hard-stop findings into the single deny file consumed downstream.
jq -s 'add' \
  "$OUT_DIR/asg-max-deny.json" \
  "$OUT_DIR/nat-deny.json" \
  "$OUT_DIR/large-instance-deny.json" \
  > "$DENY_OUT"

# Merge all review-only findings into the single warning file consumed downstream.
jq -s 'add' \
  "$OUT_DIR/nat-warn.json" \
  "$OUT_DIR/public-lb-warn.json" \
  > "$WARN_OUT"

DENY_COUNT="$(jq 'length' "$DENY_OUT")"
WARN_COUNT="$(jq 'length' "$WARN_OUT")"

# The decision file is deliberately key=value text. It is easy to read in CI logs
# and easy to archive in proof packs without parsing JSON.
{
  echo "TARGET_ENV=$TARGET_ENV"
  echo "max_asg_max_size=$MAX_ASG_MAX_SIZE"
  echo "nat_mode=$NAT_MODE"
  echo "deny_count=$DENY_COUNT"
  echo "warn_count=$WARN_COUNT"
} > "$DECISION_OUT"

# Exit 2 means the policy successfully evaluated the plan and found a blocking
# cost/blast-radius issue. This lets CI distinguish "blocked by policy" from
# script/tooling failures.
if [[ "$DENY_COUNT" -gt 0 ]]; then
  echo "COST_POLICY_DECISION=DENY" >> "$DECISION_OUT"
  echo "COST_POLICY_DECISION=DENY"
  jq . "$DENY_OUT"
  exit 2
fi

# Warnings keep exit code 0 so later gates can continue and the final risk
# classifier can raise LOW/NO_CHANGE to MEDIUM if appropriate.
echo "COST_POLICY_DECISION=ALLOW" >> "$DECISION_OUT"
echo "COST_POLICY_DECISION=ALLOW"
echo "cost_policy_results_dir=$OUT_DIR"

if [[ "$WARN_COUNT" -gt 0 ]]; then
  echo "Cost/blast-radius warnings present:"
  jq . "$WARN_OUT"
fi
