#!/usr/bin/env bash
set -Eeuo pipefail

PLAN_JSON="${1:-tfplan.json}"
ALLOW_DESTROY_FILE="${ALLOW_DESTROY_FILE:-}"
OUT_DIR="${OUT_DIR:-.}"

mkdir -p "$OUT_DIR"

DENY_OUT="$OUT_DIR/policy-deny.json"
WARN_OUT="$OUT_DIR/policy-warn.json"
DECISION_OUT="$OUT_DIR/policy-decision.txt"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for Terraform JSON plan policy checks" >&2
  exit 1
fi

if [[ ! -f "$PLAN_JSON" ]]; then
  echo "PLAN_JSON not found: $PLAN_JSON" >&2
  exit 1
fi

if [[ -n "$ALLOW_DESTROY_FILE" ]]; then
  if [[ ! -f "$ALLOW_DESTROY_FILE" ]]; then
    echo "ALLOW_DESTROY_FILE not found: $ALLOW_DESTROY_FILE" >&2
    exit 1
  fi

  # Treat exception files as change-control records, not bypass flags.
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

# Standalone SG rule resources have different schemas depending on provider generation.
# `aws_security_group_rule` uses `type=ingress`; vpc-specific ingress resources are ingress by type.
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

# Inline SG rules are still common in older modules, so keep this separate from standalone rule checks.
# Egress is intentionally not handled here.
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

# Only evaluate resources that expose tags/tags_all in planned values.
# This avoids false denies on AWS resources that cannot be tagged or do not expose tags in plan JSON.
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

# Warnings: cost/blast-radius signals for resources being created or updated.
# No-op resources are ignored.
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

jq -s 'add' \
  "$OUT_DIR/destructive-unapproved.json" \
  "$OUT_DIR/public-ingress-rules.json" \
  "$OUT_DIR/public-ingress-inline-sg.json" \
  "$OUT_DIR/missing-tags.json" \
  > "$DENY_OUT"

jq -s 'add' \
  "$OUT_DIR/warn-nat.json" \
  "$OUT_DIR/warn-asg-max.json" \
  "$OUT_DIR/warn-public-lb.json" \
  > "$WARN_OUT"

DENY_COUNT="$(jq 'length' "$DENY_OUT")"
WARN_COUNT="$(jq 'length' "$WARN_OUT")"

{
  echo "deny_count=$DENY_COUNT"
  echo "warn_count=$WARN_COUNT"
} > "$DECISION_OUT"

if [[ "$DENY_COUNT" -gt 0 ]]; then
  echo "POLICY_DECISION=DENY" >> "$DECISION_OUT"
  echo "POLICY_DECISION=DENY"
  echo "deny_count=$DENY_COUNT"
  echo "warn_count=$WARN_COUNT"
  echo "policy_results_dir=$OUT_DIR"
  echo "Policy deny findings:"
  cat "$DENY_OUT"
  exit 2
fi

echo "POLICY_DECISION=ALLOW" >> "$DECISION_OUT"
echo "POLICY_DECISION=ALLOW"
echo "deny_count=$DENY_COUNT"
echo "warn_count=$WARN_COUNT"
echo "policy_results_dir=$OUT_DIR"

if [[ "$WARN_COUNT" -gt 0 ]]; then
  echo "Policy warnings present:"
  cat "$WARN_OUT"
fi

exit 0
