# Lesson 76 Scripts

This folder contains helper scripts for local checks, review evidence, runtime health evidence, and incident recovery evidence.

## Scripts

| Script | Purpose | Changes infrastructure/state? |
| --- | --- | --- |
| `run-local-checks.sh` | Runs safe local checks. | No |
| `write-terraform-env-files.sh` | Generates temporary `backend.hcl` and `terraform.auto.tfvars` for CI. | No |
| `promotion-evidence-template.sh` | Generates valid promotion evidence JSON. | No |
| `reviewer-note-template.sh` | Generates a Markdown reviewer note from `risk-decision.json`. | No |
| `runtime-health-check.sh` | Collects read-only ALB/ASG/CloudWatch runtime evidence. | No |
| `state-snapshot.sh` | Pulls current state and plan into local evidence before recovery. | No |
| `post-incident-check.sh` | Captures post-incident plan status. | No |
| `list-state-versions.sh` | Lists S3 versions for a Terraform state key. | No |
| `incident-decision-template.sh` | Generates an incident decision note template. | No |
| `collect-capstone-proof.sh` | Copies known evidence into one timestamped folder. | No |
| `summarize-capstone.sh` | Generates `capstone-review-summary.md` from evidence. | No |

## Local checks

Run from repo root:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
```

Optional checks:

```bash
RUN_OPA=true lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
RUN_TERRAFORM=true lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
```

## Review helpers

## CI helper

```bash
AWS_REGION=eu-west-1 \
TF_STATE_BUCKET=example-tfstate \
TF_WEB_AMI_ID=ami-0123456789abcdef0 \
TF_SSM_PROXY_AMI_ID=ami-0123456789abcdef0 \
TF_GITHUB_OWNER=VlrRbn \
TF_GITHUB_REPO=DevOps \
TF_GITHUB_OIDC_PROVIDER_ARN=arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/write-terraform-env-files.sh dev
```

This script exists for GitHub Actions: `backend.hcl` and `terraform.auto.tfvars` are not stored in Git, so a clean runner must create them before `terraform init`.

## Review helpers

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/promotion-evidence-template.sh \
  l76-demo \
  dev \
  "$(git rev-parse HEAD)" \
  "https://github.com/OWNER/REPO/actions/runs/123456789" \
  > /tmp/promotion-evidence-stage.json
```

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/reviewer-note-template.sh \
  /tmp/l76-risk/risk-decision.json \
  > /tmp/l76-reviewer-note.md
```

## Runtime and incident evidence

These commands read AWS/Terraform data and write local evidence bundles:

```bash
AWS_REGION=eu-west-1 lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/runtime-health-check.sh dev
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/state-snapshot.sh dev
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/post-incident-check.sh dev
```

## Proof pack helpers

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/collect-capstone-proof.sh dev
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/summarize-capstone.sh lessons/76-capstone-end-to-end-terraform-delivery-pipeline/evidence/<folder>
```

`collect-capstone-proof.sh` copies known files only. It does not redact evidence automatically. Review the output before sharing or committing anything.

It also does not search outputs in `/tmp`. If you ran `security-policy.sh`, `cost-policy.sh`, or `risk-classifier.sh` with `OUT_DIR=/tmp/...`, copy those directories into the evidence folder before running `summarize-capstone.sh`.

## Safety Notes

- Scripts do not run `terraform apply` or `terraform destroy`.
- Runtime/state scripts can call AWS APIs and Terraform read-only commands.
- Generated evidence can contain ARNs, account IDs, DNS names, IPs, and operational metadata.
- Do not commit raw evidence unless it is intentionally redacted.
