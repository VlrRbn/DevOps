#!/usr/bin/env bash
set -Eeuo pipefail

# Security policy for Terraform JSON plans.
#
# This script is the "allowed or denied?" layer. It should not decide how much
# approval a change needs. Here we only produce:
#
# - policy-deny.json: findings that must stop apply.
# - policy-warn.json: findings that should be reviewed but do not stop apply.
# - policy-decision.txt: short human-readable summary for CI/proof-pack.
#
# The script uses jq against `terraform show -json` output. It intentionally
# avoids grep so checks follow Terraform's JSON structure instead of raw text.
usage() {
  cat >&2 <<'USAGE'
Usage:
  security-policy.sh [tfplan.json]

Environment variables:
  OUT_DIR             Output directory. Default: current directory.
  ALLOW_DESTROY_FILE  Optional JSON exception file for approved destructive addresses.

Manual example:
  OUT_DIR=/tmp/l76-policy security-policy.sh tfplan.json

Exit codes:
  0 - allowed, possibly with warnings
  1 - input/tooling error
  2 - denied by security policy
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

PLAN_JSON="${1:-tfplan.json}"
ALLOW_DESTROY_FILE="${ALLOW_DESTROY_FILE:-}"
OUT_DIR="${OUT_DIR:-.}"

mkdir -p "$OUT_DIR"

DENY_OUT="$OUT_DIR/policy-deny.json"
WARN_OUT="$OUT_DIR/policy-warn.json"
DECISION_OUT="$OUT_DIR/policy-decision.txt"

# jq is required because all policy checks are structural JSON queries.
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for Terraform JSON plan policy checks" >&2
  exit 1
fi

# Missing plan is a tooling/input failure. It is not reported as policy DENY
# because the policy never evaluated the change.
if [[ ! -f "$PLAN_JSON" ]]; then
  echo "PLAN_JSON not found: $PLAN_JSON" >&2
  exit 1
fi

# Optional exception file for approved destructive changes.
#
# This is intentionally strict:
# - exact Terraform addresses only;
# - reason and approver are required;
# - expiry must be a real calendar date and must not be in the past.
if [[ -n "$ALLOW_DESTROY_FILE" ]]; then
  if [[ ! -f "$ALLOW_DESTROY_FILE" ]]; then
    echo "ALLOW_DESTROY_FILE not found: $ALLOW_DESTROY_FILE" >&2
    exit 1
  fi

  # Treat exception files as change-control records.
  # The policy accepts only exact Terraform addresses so a reviewer can map approval to concrete resources.
  if ! jq -e '
    type == "object"
    and (.reason | type == "string" and length > 0)
    and (.approved_by | type == "string" and length > 0)
    and (.expires | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
    and (.allowed_addresses | type == "array" and length > 0)
    and all(.allowed_addresses[]; type == "string" and length > 0 and (contains("*") | not))
  ' "$ALLOW_DESTROY_FILE" >/dev/null; then
    echo "ALLOW_DESTROY_FILE is invalid. Required: reason, approved_by, expires=YYYY-MM-DD, non-empty exact allowed_addresses without wildcards." >&2
    exit 1
  fi

  EXPIRES="$(jq -r '.expires' "$ALLOW_DESTROY_FILE")"
  if ! PARSED_EXPIRES="$(date -u -d "$EXPIRES" +%F 2>/dev/null)" || [[ "$PARSED_EXPIRES" != "$EXPIRES" ]]; then
    echo "ALLOW_DESTROY_FILE expires is not a valid calendar date: $EXPIRES" >&2
    exit 1
  fi

  TODAY_UTC="$(date -u +%F)"
  if [[ "$EXPIRES" < "$TODAY_UTC" ]]; then
    echo "ALLOW_DESTROY_FILE is expired: expires=$EXPIRES today_utc=$TODAY_UTC" >&2
    exit 1
  fi
fi

# Terraform replacements contain a delete action, so `index("delete")` is the safest coarse guard.
# This intentionally catches both direct destroy and replace-in-place plans.
jq '
[
  .resource_changes[]?
  | select(.mode == "managed")
  | select(.change.actions | index("delete"))
  | {
      rule: "deny_destructive_change",
      address: .address,
      type: .type,
      actions: .change.actions
    }
]
' "$PLAN_JSON" > "$OUT_DIR/destructive.json"

if [[ -n "$ALLOW_DESTROY_FILE" ]]; then
  # Keep both raw destructive findings and effective unapproved findings.
  # The raw file is evidence; the effective file is what actually contributes to DENY.
  jq -s '
    .[0] as $violations
    | (.[1].allowed_addresses // []) as $allowed
    | [
        $violations[]
        | select(.address as $addr | ($allowed | index($addr) | not))
      ]
  ' "$OUT_DIR/destructive.json" "$ALLOW_DESTROY_FILE" > "$OUT_DIR/destructive-unapproved.json"
else
  cp "$OUT_DIR/destructive.json" "$OUT_DIR/destructive-unapproved.json"
fi

# DENY: public ingress in standalone security group rule resources.
#
# Standalone SG rule resources have different schemas depending on provider
# generation. `aws_security_group_rule` uses `type=ingress`; newer VPC-specific
# ingress resources are ingress by resource type. This query handles both shapes.
jq '
[
  .resource_changes[]?
  | select(.mode == "managed")
  | select(.type == "aws_security_group_rule" or .type == "aws_vpc_security_group_ingress_rule")
  | select((.change.actions | index("delete")) | not)
  | . as $r
  | ($r.change.after // {}) as $after
  | select(
      ($r.type == "aws_vpc_security_group_ingress_rule")
      or ($r.type == "aws_security_group_rule" and (($after.type // "") == "ingress"))
    )
  | select(
      (($after.cidr_blocks // []) | index("0.0.0.0/0"))
      or (($after.ipv6_cidr_blocks // []) | index("::/0"))
      or ($after.cidr_ipv4? == "0.0.0.0/0")
      or ($after.cidr_ipv6? == "::/0")
    )
  | {
      rule: "deny_public_ingress",
      address: $r.address,
      type: $r.type,
      cidr_blocks: ($after.cidr_blocks // []),
      ipv6_cidr_blocks: ($after.ipv6_cidr_blocks // []),
      cidr_ipv4: ($after.cidr_ipv4 // null),
      cidr_ipv6: ($after.cidr_ipv6 // null),
      from_port: ($after.from_port // null),
      to_port: ($after.to_port // null),
      protocol: ($after.protocol // null)
    }
]
' "$PLAN_JSON" > "$OUT_DIR/public-ingress-rules.json"

# DENY: public ingress embedded directly inside aws_security_group.
#
# Inline SG rules are common in older modules, keep this separate from standalone
# rule checks. Egress is intentionally not handled here.
jq '
[
  .resource_changes[]?
  | select(.mode == "managed")
  | select(.type == "aws_security_group")
  | select((.change.actions | index("delete")) | not)
  | . as $r
  | (($r.change.after.ingress // [])[]? ) as $ingress
  | select(
      (($ingress.cidr_blocks // []) | index("0.0.0.0/0"))
      or (($ingress.ipv6_cidr_blocks // []) | index("::/0"))
    )
  | {
      rule: "deny_public_ingress_inline_sg",
      address: $r.address,
      type: $r.type,
      cidr_blocks: ($ingress.cidr_blocks // []),
      ipv6_cidr_blocks: ($ingress.ipv6_cidr_blocks // []),
      from_port: ($ingress.from_port // null),
      to_port: ($ingress.to_port // null),
      protocol: ($ingress.protocol // null)
    }
]
' "$PLAN_JSON" > "$OUT_DIR/public-ingress-inline-sg.json"

# DENY: missing required tags on taggable resources.
#
# Only evaluate resources that expose tags/tags_all in planned values. That avoids
# false denies on resources that cannot be tagged or do not expose tags in plan JSON.
jq '
def has_required_tags($tags):
  ($tags // {}) as $t
  | (($t.Project? // "") | type == "string" and length > 0)
  and (($t.Environment? // "") | type == "string" and length > 0)
  and (($t.ManagedBy? // "") | type == "string" and length > 0);

[
  .resource_changes[]?
  | select(.mode == "managed")
  | select((.change.actions | index("delete")) | not)
  | . as $r
  | ($r.change.after // {}) as $after
  | ($after.tags // $after.tags_all // null) as $tags
  | select($tags != null)
  | select(has_required_tags($tags) | not)
  | {
      rule: "deny_missing_required_tags",
      address: $r.address,
      type: $r.type,
      tags: ($tags // {})
    }
]
' "$PLAN_JSON" > "$OUT_DIR/missing-tags.json"

# WARN: NAT Gateway cost/blast-radius signal.
#
# This is not a hard security deny. NAT may be correct, but it should be visible
# in the review because it adds cost and routing complexity.
jq '
def is_create_or_update:
  ((.change.actions | index("delete")) | not)
  and ((.change.actions | index("create")) or (.change.actions | index("update")));

[
  .resource_changes[]?
  | select(.mode == "managed")
  | select(is_create_or_update)
  | select(.type == "aws_nat_gateway")
  | {
      rule: "warn_nat_gateway_cost",
      address: .address,
      actions: .change.actions
    }
]
' "$PLAN_JSON" > "$OUT_DIR/warn-nat.json"

# WARN: ASG max_size above the broad review threshold.
#
# "Review this capacity increase", not "block it".
jq '
def is_create_or_update:
  ((.change.actions | index("delete")) | not)
  and ((.change.actions | index("create")) or (.change.actions | index("update")));

[
  .resource_changes[]?
  | select(.mode == "managed")
  | select(is_create_or_update)
  | select(.type == "aws_autoscaling_group")
  | select((.change.after.max_size // 0) > 4)
  | {
      rule: "warn_asg_max_size_high",
      address: .address,
      max_size: .change.after.max_size
    }
]
' "$PLAN_JSON" > "$OUT_DIR/warn-asg-max.json"

# WARN: public load balancer exposure.
#
# Public load balancers can be expected in real systems, so this does not deny.
# It gives the reviewer a clear signal that external exposure is part of the plan.
jq '
def is_create_or_update:
  ((.change.actions | index("delete")) | not)
  and ((.change.actions | index("create")) or (.change.actions | index("update")));

[
  .resource_changes[]?
  | select(.mode == "managed")
  | select(is_create_or_update)
  | select(.type == "aws_lb")
  | select((.change.after.internal // true) == false)
  | {
      rule: "warn_public_load_balancer",
      address: .address,
      name: (.change.after.name // null)
    }
]
' "$PLAN_JSON" > "$OUT_DIR/warn-public-lb.json"

# Combine all hard-stop findings. The risk classifier expects one deny file, so
# each individual rule writes a temporary JSON file and this block merges them.
jq -s 'add' \
  "$OUT_DIR/destructive-unapproved.json" \
  "$OUT_DIR/public-ingress-rules.json" \
  "$OUT_DIR/public-ingress-inline-sg.json" \
  "$OUT_DIR/missing-tags.json" \
  > "$DENY_OUT"

# Combine all review-only findings into one warnings file.
jq -s 'add' \
  "$OUT_DIR/warn-nat.json" \
  "$OUT_DIR/warn-asg-max.json" \
  "$OUT_DIR/warn-public-lb.json" \
  > "$WARN_OUT"

DENY_COUNT="$(jq 'length' "$DENY_OUT")"
WARN_COUNT="$(jq 'length' "$WARN_OUT")"

# Keep a compact text summary for CI logs and proof-pack evidence.
{
  echo "deny_count=$DENY_COUNT"
  echo "warn_count=$WARN_COUNT"
} > "$DECISION_OUT"

# Exit 2 means "policy evaluated the plan and blocked it". This is distinct from
# exit 1 input/tooling failures and lets CI/reporting handle the cases correctly.
if [[ "$DENY_COUNT" -gt 0 ]]; then
  echo "POLICY_DECISION=DENY" >> "$DECISION_OUT"
  echo "POLICY_DECISION=DENY"
  echo "deny_count=$DENY_COUNT"
  echo "warn_count=$WARN_COUNT"
  echo "terraform_plan_policy_results_dir=$OUT_DIR"
  echo "Policy deny findings:"
  cat "$DENY_OUT"
  exit 2
fi

# Warnings do not fail this script. They are passed forward to the risk
# classifier, which can raise review level without blocking apply.
echo "POLICY_DECISION=ALLOW" >> "$DECISION_OUT"
echo "POLICY_DECISION=ALLOW"
echo "deny_count=$DENY_COUNT"
echo "warn_count=$WARN_COUNT"
echo "terraform_plan_policy_results_dir=$OUT_DIR"

if [[ "$WARN_COUNT" -gt 0 ]]; then
  echo "Policy warnings present:"
  cat "$WARN_OUT"
fi

exit 0
