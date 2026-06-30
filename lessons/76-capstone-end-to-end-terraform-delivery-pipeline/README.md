# Lesson 76: Capstone End-to-End Terraform Delivery Pipeline

This folder contains the final Terraform delivery capstone. It connects the previous lessons into one auditable workflow: checks, plan artifacts, policies, cost gates, risk classification, approval, exact-plan apply, verification, runtime health, and recovery evidence.

## Included

- `lesson.en.md` and `lesson.ru.md` - full lesson text
- `proof-pack.en.md` and `proof-pack.ru.md` - evidence checklist
- `ci` - GitHub Actions templates: PR checks, promotion, drift
- `scripts/` - local checks and evidence helpers
- `policies` - security, cost, OPA, and risk policies
- `runbooks/` - recovery and incident procedures
- `lab_76/` - Terraform/Packer lab

## Quick Checks

From repo root:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
```

Optional deeper checks:

```bash
RUN_OPA=true lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
RUN_TERRAFORM=true lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
```

## Main Flow

```text
local checks
-> PR checks
-> saved tfplan
-> tfplan.json
-> security policy
-> cost policy
-> risk classifier
-> review artifacts
-> approval
-> apply exact tfplan
-> post-apply drift check
-> runtime health evidence
-> proof pack
```

## Safety Notes

- Do not run `apply` without reviewing `tfplan.txt`, policy outputs, cost outputs, and `risk-decision.md`.
- Do not apply a stale PR plan artifact.
- Apply the exact saved `tfplan` generated from the protected branch.
- `tfplan.sha256` detects accidental mismatch between reviewed and applied files, but it is not a full trust boundary if the whole artifact can be replaced.
- For `stage`/`prod`, record the previous environment workflow run URL as promotion evidence.
- The promotion workflow verifies the source workflow run through the GitHub API, downloads the source apply artifact, and validates `promotion-manifest.json`.
- Source promotion evidence must match the same commit SHA, `release_id`, source environment, successful apply, and clean post-apply drift check.
- Apply artifacts are uploaded with `if: always()` so failed apply/post-apply checks still leave evidence.
- Treat raw evidence as sensitive: it can contain ARNs, account IDs, DNS names, IPs, and internal metadata.
- `ci/` files are templates. Review and copy them into `.github/workflows/` only when ready.
- GitHub Actions in `ci/` are pinned by commit SHA. When upgrading an action, resolve the new tag SHA deliberately and update the workflow in a separate review.
- `lesson76-drift-check.yml` is read-only, uses plan role only, fails on drift exit code `2`, and uploads text/JSON drift evidence.
- Drift workflow does not upload the binary `tfplan` because drift plans are evidence, not apply artifacts.
- `backend.hcl`, `terraform.tfvars`, and `terraform.auto.tfvars` are intentionally ignored. CI generates temporary copies with `scripts/write-terraform-env-files.sh`.

## CI Variables

The promotion and drift templates expect these GitHub Variables:

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

These optional variables override repository auto-detection:

```text
TF_GITHUB_OWNER
TF_GITHUB_REPO
```

GitHub Environment secrets must contain apply role ARNs:

```text
TF_APPLY_ROLE_ARN_DEV
TF_APPLY_ROLE_ARN_STAGE
TF_APPLY_ROLE_ARN_PROD
```

## Evidence Helpers

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/collect-capstone-proof.sh dev
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/summarize-capstone.sh lessons/76-capstone-end-to-end-terraform-delivery-pipeline/evidence/<folder>
```
