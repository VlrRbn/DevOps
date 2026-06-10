# Lesson 70: Policy as Code on Terraform JSON Plan

This lesson turns Terraform's saved JSON plan into a policy gate before apply.

It continues:

- Lesson 68: controlled Terraform apply pipeline
- Lesson 69: separate least-privilege plan/apply IAM roles
- Lesson 70: plan policy checks before approval/apply

## What Is Included

- `lesson.en.md` and `lesson.ru.md` - full lesson text
- `policies/terraform-plan-policy.sh` - jq-based policy engine for `tfplan.json`
- `policies/test-policy.sh` - local jq policy tests using fixture plans
- `policies/test-opa.sh` - optional OPA/Rego tests against the same core fixtures
- `policies/tests/` - safe, warning, deny, replacement, ingress/egress, tag, and exception fixtures
- `policies/opa/terraform.rego` - optional OPA/Rego v1 policy example
- `ci/lesson70-terraform-apply-dev.yml` - GitHub Actions template with policy gate
- `proof-pack.en.md` and `proof-pack.ru.md` - evidence checklist
- `lab_70/` - copied Terraform/Packer lab used for real plan generation

## Quick Check

From repo root:

```bash
lessons/70-policy-as-code-terraform-json-plan/policies/test-policy.sh
# Optional, if opa is installed:
lessons/70-policy-as-code-terraform-json-plan/policies/test-opa.sh
```

Expected mandatory output:

```text
policy tests passed
```

Optional OPA output, if `opa` is installed:

```text
opa policy tests passed
```

## Real Plan Flow

From Terraform env directory:

```bash
cd lessons/70-policy-as-code-terraform-json-plan/lab_70/terraform/envs
terraform init -reconfigure -backend-config=backend.hcl
terraform plan -out=tfplan
terraform show -no-color tfplan > tfplan.txt
terraform show -json tfplan > tfplan.json
OUT_DIR=policy-results ../../../policies/terraform-plan-policy.sh tfplan.json
```

The policy script always prints a short console summary:

```text
POLICY_DECISION=ALLOW|DENY
deny_count=<number>
warn_count=<number>
policy_results_dir=policy-results
```

Policy output files:

- `policy-results/policy-decision.txt`
- `policy-results/policy-output.txt`
- `policy-results/policy-deny.json`
- `policy-results/policy-warn.json`
- `policy-results/destructive.json`
- `policy-results/destructive-unapproved.json`
- `policy-results/public-ingress-rules.json`
- `policy-results/public-ingress-inline-sg.json`
- `policy-results/missing-tags.json`

## Exit Codes

- `0`: plan allowed
- `1`: script/input error
- `2`: policy denied the plan

## CI Template

`ci/lesson70-terraform-apply-dev.yml` is intentionally stored as a lesson template.

Copy it to `.github/workflows/lesson70-terraform-apply-dev.yml` only when you are ready to run it.

The template does this order:

1. generate saved plan
2. convert to `tfplan.json`
3. run policy
4. upload plan and policy artifacts
5. wait for GitHub Environment approval
6. apply exact saved plan
7. run post-apply drift check

## Safety Notes

- Do not commit real `tfplan.json` from production without review; it may contain sensitive values.
- Destroy exceptions must use exact Terraform addresses, not wildcards.
- `destructive-unapproved.json` contains destructive changes that are not covered by an approved exception.
- Destroy exception expiry is checked against the current UTC date.
- Invalid or expired destroy exception files fail as input errors.
- Required governance tags must be present and non-empty.
- Public ingress checks do not block egress rules; outbound exposure needs a separate policy if you want to restrict it.
- Warnings do not block, but they should still be reviewed. Warning rules intentionally ignore `no-op` resources and only report create/update changes.
- The policy gate complements IAM, approval, drift detection, and human review. It does not replace them.
