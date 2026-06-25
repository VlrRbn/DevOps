#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  cost-policy.sh <tfplan.json> <target_env>

Exit codes:
  0 - allowed, possibly with warnings
  1 - input/tooling error
  2 - denied by cost/blast-radius policy
 64 - usage/input shape error
USAGE
}

PLAN_JSON="${1:-}"
TARGET_ENV="${2:-}"
OUT_DIR="${OUT_DIR:-lessons/74-disaster-recovery-and-incident-runbooks/policies/cost-policy-results}"

if [[ -z "$PLAN_JSON" || -z "$TARGET_ENV" ]]; then
  usage
  exit 64
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for cost policy checks" >&2
  exit 1
fi

if [[ ! -f "$PLAN_JSON" ]]; then
  echo "PLAN_JSON not found: $PLAN_JSON" >&2
  exit 1
fi

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

DENY_OUT="$OUT_DIR/cost-deny.json"
WARN_OUT="$OUT_DIR/cost-warn.json"
DECISION_OUT="$OUT_DIR/cost-decision.txt"

# This lab intentionally blocks ASG max_size above the environment limit.
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

# This lab intentionally flags NAT Gateway usage.
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

if [[ "$NAT_MODE" == "deny" ]]; then
  cp "$OUT_DIR/nat-signal.json" "$OUT_DIR/nat-deny.json"
  echo '[]' > "$OUT_DIR/nat-warn.json"
else
  echo '[]' > "$OUT_DIR/nat-deny.json"
  cp "$OUT_DIR/nat-signal.json" "$OUT_DIR/nat-warn.json"
fi

# This lab intentionally blocks large 2xlarge+ instance shapes regardless of family.
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

# Public load balancers are not always wrong, but they expand exposure and review scope.
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

jq -s 'add' \
  "$OUT_DIR/asg-max-deny.json" \
  "$OUT_DIR/nat-deny.json" \
  "$OUT_DIR/large-instance-deny.json" \
  > "$DENY_OUT"

jq -s 'add' \
  "$OUT_DIR/nat-warn.json" \
  "$OUT_DIR/public-lb-warn.json" \
  > "$WARN_OUT"

DENY_COUNT="$(jq 'length' "$DENY_OUT")"
WARN_COUNT="$(jq 'length' "$WARN_OUT")"

{
  echo "TARGET_ENV=$TARGET_ENV"
  echo "max_asg_max_size=$MAX_ASG_MAX_SIZE"
  echo "nat_mode=$NAT_MODE"
  echo "deny_count=$DENY_COUNT"
  echo "warn_count=$WARN_COUNT"
} > "$DECISION_OUT"

if [[ "$DENY_COUNT" -gt 0 ]]; then
  echo "COST_POLICY_DECISION=DENY" >> "$DECISION_OUT"
  echo "COST_POLICY_DECISION=DENY"
  jq . "$DENY_OUT"
  exit 2
fi

echo "COST_POLICY_DECISION=ALLOW" >> "$DECISION_OUT"
echo "COST_POLICY_DECISION=ALLOW"

if [[ "$WARN_COUNT" -gt 0 ]]; then
  echo "Cost/blast-radius warnings present:"
  jq . "$WARN_OUT"
fi
