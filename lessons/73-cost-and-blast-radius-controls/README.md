# Lesson 73: Cost & Blast-Radius Controls

This lesson continues the Terraform delivery chain from lessons 70-72 and adds pre-apply controls for financial and operational blast radius.

The main point: a Terraform plan can be syntactically valid, policy-compliant, and still too expensive or too wide-impact for the target environment.

The lab intentionally uses small deterministic JSON plan fixtures for expensive scenarios such as NAT Gateway or large instances. This lets you test the controls without creating costly AWS resources.

## What Is Included

- `lesson.en.md` and `lesson.ru.md` - full lesson text
- `proof-pack.en.md` and `proof-pack.ru.md` - evidence checklist
- `ci/lesson73-cost-guard.yml` - lesson copy of the GitHub Actions cost/blast-radius workflow
- `policies/terraform-plan-policy.sh` - baseline security/change policy from previous lessons
- `policies/cost-policy.sh` - lesson 73 cost and blast-radius policy
- `policies/test-policy.sh` - baseline policy tests
- `policies/test-cost-policy.sh` - cost policy tests
- `policies/test-opa.sh` - optional OPA/Rego tests
- `lab_73/terraform/envs/dev` - dev root module
- `lab_73/terraform/envs/stage` - stage root module
- `lab_73/terraform/envs/prod` - prod root module
- `lab_73/terraform/modules/network` - shared module used by all roots

## Risk Model

| Environment | ASG max_size limit | NAT Gateway | Public ALB | Intent |
| --- | ---: | --- | --- | --- |
| `dev` | 2 | deny | warn | cheap by default |
| `stage` | 3 | warn | warn | production-like but controlled |
| `prod` | 4 | warn | warn | deliberate changes only |

The thresholds are training values. In a real account, align them with actual budgets, quotas, and service ownership.

## Required Local Tools

- Terraform
- Packer
- `jq`
- OPA, only for `policies/test-opa.sh`
- AWS CLI, only for optional budget/quota evidence

## Quick Checks

From repo root:

```bash
terraform fmt -check -recursive lessons/73-cost-and-blast-radius-controls/lab_73/terraform
packer fmt -check -recursive lessons/73-cost-and-blast-radius-controls/lab_73/packer
lessons/73-cost-and-blast-radius-controls/policies/test-policy.sh
lessons/73-cost-and-blast-radius-controls/policies/test-cost-policy.sh
lessons/73-cost-and-blast-radius-controls/policies/test-opa.sh
```

Run module tests:

```bash
TF_DATA_DIR=/tmp/l73-module-test-data \
terraform -chdir=lessons/73-cost-and-blast-radius-controls/lab_73/terraform/modules/network \
  init -backend=false -input=false -no-color

TF_DATA_DIR=/tmp/l73-module-test-data \
terraform -chdir=lessons/73-cost-and-blast-radius-controls/lab_73/terraform/modules/network \
  test -no-color
```

Validate env roots without remote state:

```bash
for env in dev stage prod; do
  TF_DATA_DIR="/tmp/l73-${env}-data" \
  terraform -chdir="lessons/73-cost-and-blast-radius-controls/lab_73/terraform/envs/${env}" \
    init -backend=false -input=false -no-color

  TF_DATA_DIR="/tmp/l73-${env}-data" \
  terraform -chdir="lessons/73-cost-and-blast-radius-controls/lab_73/terraform/envs/${env}" \
    validate -no-color
done
```

## Cost Policy Examples

```bash
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-safe-plan.json \
  dev
```

Expected: allow.

```bash
lessons/73-cost-and-blast-radius-controls/policies/cost-policy.sh \
  lessons/73-cost-and-blast-radius-controls/policies/tests/cost-high-asg-plan.json \
  dev
```

Expected: deny.

## CI Workflow

`ci/lesson73-cost-guard.yml` is the lesson copy. The active GitHub Actions workflow lives at `.github/workflows/lesson73-cost-guard.yml` when installed in the repository. Keep both files in sync if you edit the workflow.

The workflow is intentionally AWS-free. It validates the lab and proves the policies before you wire them into a real apply pipeline.

For Infracost checks, prefer scanning the saved `tfplan.json` from the target environment. Scanning the whole Terraform tree can produce local module boundary diagnostics in this lesson layout. Security note: scanning `tfplan.json` sends plan metadata to the external Infracost service, so use it only for lab/non-sensitive plans.

It checks Terraform/Packer formatting and validation, shell syntax, module native tests, env root validation without remote state, baseline policy tests, cost policy tests, optional OPA tests, and sample evidence generation.

## Safety Notes

- AWS Budgets are not real-time apply blockers.
- Infracost estimates are evidence, not invoices.
- Cost warnings must still be visible in artifacts.
- Do not commit raw billing/account evidence unless redacted.
- Do not commit generated `artifacts/`, `policy-results/`, or `cost-policy-results/` directories.
