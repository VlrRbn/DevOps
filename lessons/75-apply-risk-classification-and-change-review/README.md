# Lesson 75: Apply Risk Classification & Change Review

This lesson continues the Terraform delivery track and adds a final risk review artifact before apply.

Main idea: policy gates answer whether a plan is allowed; risk classification answers how much approval the plan needs.

## Included

- `lesson.en.md` and `lesson.ru.md` - full lesson text
- `proof-pack.en.md` and `proof-pack.ru.md` - evidence checklist
- `ci/lesson75-real-plan-risk-review.yml` - GitHub Actions template for real AWS-backed plan risk review
- `scripts/` - helper scripts for local checks, promotion evidence, and reviewer notes
- `policies/risk-classifier.sh` - final apply risk classifier
- `.github/workflows/lesson75-risk-review.yml` - active local-check workflow copy
- `.github/workflows/lesson75-real-plan-risk-review.yml` - active real-plan workflow copy
- `policies/test-risk-classifier.sh` - classifier tests
- `policies/terraform-plan-policy.sh` - inherited security/change policy
- `policies/cost-policy.sh` - inherited cost/blast-radius policy
- `lab_75/` - Terraform/Packer lab copied from the previous delivery chain


## Quick Checks

From repo root:

```bash
lessons/75-apply-risk-classification-and-change-review/scripts/run-local-checks.sh
```

Or run the checks manually:

```bash
terraform fmt -check -recursive lessons/75-apply-risk-classification-and-change-review/lab_75/terraform
packer fmt -check -recursive lessons/75-apply-risk-classification-and-change-review/lab_75/packer
bash -n lessons/75-apply-risk-classification-and-change-review/policies/*.sh
shellcheck lessons/75-apply-risk-classification-and-change-review/policies/*.sh
lessons/75-apply-risk-classification-and-change-review/policies/test-policy.sh
lessons/75-apply-risk-classification-and-change-review/policies/test-cost-policy.sh
lessons/75-apply-risk-classification-and-change-review/policies/test-risk-classifier.sh
lessons/75-apply-risk-classification-and-change-review/policies/test-opa.sh
```

Run module tests:

```bash
TF_DATA_DIR=/tmp/l75-module-test-data \
terraform -chdir=lessons/75-apply-risk-classification-and-change-review/lab_75/terraform/modules/network \
  init -backend=false -input=false -no-color

TF_DATA_DIR=/tmp/l75-module-test-data \
terraform -chdir=lessons/75-apply-risk-classification-and-change-review/lab_75/terraform/modules/network \
  test -no-color
```

Validate env roots without remote state:

```bash
for env in dev stage prod; do
  TF_DATA_DIR="/tmp/l75-${env}-data" \
  terraform -chdir="lessons/75-apply-risk-classification-and-change-review/lab_75/terraform/envs/${env}" \
    init -backend=false -input=false -no-color

  TF_DATA_DIR="/tmp/l75-${env}-data" \
  terraform -chdir="lessons/75-apply-risk-classification-and-change-review/lab_75/terraform/envs/${env}" \
    validate -no-color
done
```

## Real Plan Risk Review Example

```bash
cd lessons/75-apply-risk-classification-and-change-review/lab_75/terraform/envs/dev

terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json

mkdir -p ../../../../evidence/policy-results \
         ../../../../evidence/cost-policy-results \
         ../../../../evidence/risk-results

OUT_DIR=../../../../evidence/policy-results \
../../../../policies/terraform-plan-policy.sh tfplan.json

OUT_DIR=../../../../evidence/cost-policy-results \
../../../../policies/cost-policy.sh tfplan.json dev

POLICY_DIR=../../../../evidence/policy-results \
COST_DIR=../../../../evidence/cost-policy-results \
OUT_DIR=../../../../evidence/risk-results \
REQUIRE_PROMOTION_EVIDENCE=false \
../../../../policies/risk-classifier.sh tfplan.json dev
```

## Real Plan Workflow

The active workflow `.github/workflows/lesson75-real-plan-risk-review.yml` runs the same chain in GitHub Actions:

```text
OIDC assume plan role
-> write backend.hcl and terraform.auto.tfvars
-> terraform init against remote S3 backend
-> terraform plan -out=tfplan
-> terraform show -json tfplan
-> security/change policy
-> cost/blast-radius policy
-> risk-classifier
-> upload real plan/policy/cost/risk artifacts
```

Required repository variables:

```text
AWS_REGION
TF_STATE_BUCKET
TF_WEB_AMI_ID
TF_SSM_PROXY_AMI_ID
TF_GITHUB_OIDC_PROVIDER_ARN
TF_PLAN_ROLE_ARN_DEV
TF_PLAN_ROLE_ARN_STAGE
TF_PLAN_ROLE_ARN_PROD
```

Optional repository variables:

```text
TF_GITHUB_OWNER
TF_GITHUB_REPO
```

`dev` does not require promotion evidence. `stage` and `prod` require a repo-relative `promotion_evidence_path` so the classifier can validate promotion context.

The classifier uses a fail-closed model by default:

- missing or malformed `policy-deny.json`, `policy-warn.json`, `cost-deny.json`, or `cost-warn.json` -> `BLOCKED`;
- `NO_CHANGE` is allowed only after required policy/cost inputs exist and are valid;
- `risk` is separate from `approval_required` and `approval_level`;
- `reason_codes` explain why the decision was made.
- promotion evidence for stage/prod is validated as JSON with matching `release_id`, matching `source_env`, `status=passed`, and a Git-like `commit_sha`.

## Safety Notes

- The CI templates do not run `apply`.
- `BLOCKED` must stop apply.
- Missing policy/cost outputs must block apply unless `ALLOW_MISSING_POLICY_OUTPUTS=true` is intentionally set for a local demo.
- `REQUIRE_PROMOTION_EVIDENCE=false` must not be used globally in CI; stage/prod managed changes require promotion evidence.
- `EMERGENCY` is not a shortcut around evidence; it requires `INCIDENT_RECORD_FILE` with an incident/break-glass record.
- Stage/prod risk classification should include valid promotion evidence when managed changes exist.
- Generated risk artifacts may include resource names and operational metadata; review before sharing.
