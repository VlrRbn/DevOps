# Lesson 68 Proof Pack - Controlled Terraform Apply Pipeline

Use this file as the checklist for the evidence you keep after the lab.

Recommended local folder name:

```bash
mkdir -p lessons/68-controlled-terraform-apply-pipeline/evidence/l68-YYYYmmdd_HHMMSS
```

Do not commit raw evidence if it contains account IDs, ARNs, instance IDs, bucket names, or internal endpoints. Redact first if you want to publish it.

## 1. Bootstrap Evidence

Capture the trusted local bootstrap outputs:

```bash
terraform output -no-color > evidence/l68-YYYYmmdd_HHMMSS/bootstrap-outputs-redacted.txt
terraform output -raw tf_plan_role_arn > evidence/l68-YYYYmmdd_HHMMSS/plan-role-arn-redacted.txt
terraform output -raw tf_apply_role_arn > evidence/l68-YYYYmmdd_HHMMSS/apply-role-arn-redacted.txt
```

Redact account ID and unique role suffixes before committing.

## 2. GitHub Environment Evidence

Save a short note or screenshot proving:

- Environment name is `terraform-dev`
- Required reviewers or wait timer are configured
- The apply workflow uses that environment

Suggested note file:

```text
evidence/l68-YYYYmmdd_HHMMSS/github-environment.txt
```

## 3. Repository Variables Evidence

Save a redacted list of variables:

```text
AWS_REGION=eu-west-1
TF_STATE_BUCKET=<redacted-tfstate-bucket>
TF_PLAN_ROLE_ARN=arn:aws:iam::<account-id-redacted>:role/<redacted-plan-role>
TF_APPLY_ROLE_ARN=arn:aws:iam::<account-id-redacted>:role/<redacted-apply-role>
TF_WEB_AMI_ID=ami-xxxxxxxxxxxxxxx
TF_SSM_PROXY_AMI_ID=ami-xxxxxxxxxxxxxxx
```

Do not store real secret values. AMI IDs are not usually secrets, but redact them if the repo is public and you want a clean public artifact.

## 4. Workflow Run Evidence

Download or copy these GitHub Actions artifacts:

```text
lesson68-terraform-plan-dev
lesson68-terraform-apply-dev
```

Expected files:

- `plan.txt`
- `tfplan.txt`
- `tfplan.json`
- `destructive_changes.json`
- `apply.txt`
- `post_apply_plan.txt`
- `post_apply_exitcode.txt`

## 5. Decision Note

Create a short decision file:

```text
mode: controlled apply
source_branch: main
environment: terraform-dev
decision: GO
reason: saved plan reviewed, environment approved, apply completed, post-apply drift check clean
post_apply_exit_code: 0
run_url: <github-actions-run-url>
operator: <name-or-handle>
timestamp: <UTC timestamp>
```

## 6. Failure Evidence

If a guard blocks the apply, keep the failed artifact too. Useful examples:

- missing repository variable
- environment approval rejected
- destructive action blocked
- post-apply plan exit code `2`
- Terraform provider or backend error

A blocked apply is valid proof when it shows the guardrail worked.
