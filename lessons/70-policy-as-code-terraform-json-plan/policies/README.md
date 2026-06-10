# Terraform Plan Policy

This folder contains the policy layer for Lesson 70.

The primary implementation is `terraform-plan-policy.sh`: a jq-based evaluator for Terraform saved JSON plans.

## Files

- `terraform-plan-policy.sh`
  - evaluates `tfplan.json`
  - writes deny/warn/decision artifacts
  - exits `2` when policy denies the plan
  - exits `1` for script/input problems
- `test-policy.sh`
  - runs jq-policy fixtures
  - covers deny, warn, false-positive, and exception cases
- `test-opa.sh`
  - optional OPA/Rego smoke test runner
  - requires `opa`
- `allow-destroy.example.json`
  - exact-address destroy exception example
- `opa/terraform.rego`
  - optional Rego v1 example for core deny rules
- `tests/`
  - fixture `tfplan.json` files used by both test runners

## Policy Contract

The jq policy treats these as hard denies:

- direct destroy and replacement (`actions` contains `delete`)
- public ingress from `0.0.0.0/0` or `::/0`
- missing or empty governance tags: `Project`, `Environment`, `ManagedBy`

The jq policy treats these as warnings:

- created or updated NAT Gateway
- created or updated ASG with `max_size > 4`
- created or updated public ALB

Warnings intentionally ignore `no-op` resources.

## Exit Codes

- `0`: policy allowed the plan
- `1`: invalid input or script/runtime problem
- `2`: policy ran successfully and denied the plan

This split matters in CI. Exit `1` means the gate itself is broken or called incorrectly. Exit `2` means the gate worked and found a forbidden change.

## Destroy Exceptions

Destroy exceptions are intentionally narrow:

```json
{
  "reason": "retire obsolete alarm after review",
  "approved_by": "CHANGE-1234",
  "expires": "2099-12-31",
  "allowed_addresses": [
    "module.network.aws_cloudwatch_metric_alarm.old_alarm"
  ]
}
```

Rules:

- exact Terraform addresses only
- no wildcards
- non-empty `reason`
- non-empty `approved_by`
- valid `expires` date in `YYYY-MM-DD`
- expiry is checked against current UTC date

The exception only removes matching addresses from `destructive-unapproved.json`. Other deny rules still apply.

## Run Locally

From repo root:

```bash
lessons/70-policy-as-code-terraform-json-plan/policies/test-policy.sh
```

Optional OPA check:

```bash
lessons/70-policy-as-code-terraform-json-plan/policies/test-opa.sh
```

Run policy against a real saved plan:

```bash
cd lessons/70-policy-as-code-terraform-json-plan/lab_70/terraform/envs
terraform show -json tfplan > tfplan.json
OUT_DIR=policy-results ../../../policies/terraform-plan-policy.sh tfplan.json
```

## Output Artifacts

Main artifacts:

- `policy-decision.txt`
- `policy-deny.json`
- `policy-warn.json`

Rule-specific artifacts:

- `destructive.json`
- `destructive-unapproved.json`
- `public-ingress-rules.json`
- `public-ingress-inline-sg.json`
- `missing-tags.json`
- `warn-nat.json`
- `warn-asg-max.json`
- `warn-public-lb.json`

## Design Notes

- The policy operates on a saved binary plan converted with `terraform show -json`.
- Replacement is treated as destructive because Terraform represents it with a `delete` action.
- Tag checks only apply to resources that expose `tags` or `tags_all` in planned values.
- OPA/Rego currently mirrors core deny examples.
- jq remains the authoritative lesson implementation.
