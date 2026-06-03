# Lesson 68 - Controlled Terraform Apply Pipeline

This lesson turns the previous Terraform plan/drift work into a controlled apply workflow.

The goal is not to make apply fully automatic. The goal is to make apply repeatable, approved, artifact-backed, and safe enough for a real team workflow.

## Files

- `lesson.en.md` - English lesson
- `lesson.ru.md` - Russian lesson
- `proof-pack.en.md` - proof pack checklist in English
- `proof-pack.ru.md` - proof pack checklist in Russian
- `ci/terraform-apply-dev.yml` - workflow template for controlled apply
- `lab_68/terraform/` - Terraform lab copied forward and adjusted for lesson 68

## Active Workflow

The template is also installed as:

```text
.github/workflows/lesson68-terraform-apply-dev.yml
```

The workflow is intentionally manual and split into two jobs:

- `plan-dev` runs through `workflow_dispatch` from `main`
- `plan-dev` requires `confirm_apply=APPLY`
- `plan-dev` runs fmt and native tests before AWS credentials
- `plan-dev` assumes the lower-power plan role
- `plan-dev` creates `tfplan`, `tfplan.txt`, and `tfplan.json`
- `plan-dev` uploads `lesson68-terraform-plan-dev` for review
- `apply-dev` waits for GitHub Environment `terraform-dev` approval
- `apply-dev` assumes the environment-scoped apply role
- `apply-dev` downloads and applies the exact saved `tfplan` artifact
- JSON plan guard blocks destroy/replacement unless `allow_destroy=ALLOW_DESTROY`
- post-apply verification runs `terraform plan -detailed-exitcode`
- both jobs upload evidence artifacts

## Required GitHub Variables

Set these as repository variables before running the workflow:

```text
AWS_REGION
TF_STATE_BUCKET
TF_PLAN_ROLE_ARN
TF_APPLY_ROLE_ARN
TF_WEB_AMI_ID
TF_SSM_PROXY_AMI_ID
```

`TF_PLAN_ROLE_ARN` and `TF_APPLY_ROLE_ARN` come from Terraform outputs after the initial local/trusted bootstrap:

```bash
terraform output -raw tf_plan_role_arn
terraform output -raw tf_apply_role_arn
```

## Bootstrap Note

The workflow cannot create its own first plan/apply roles. First create or update the lab from a trusted local/admin session, then copy the output role ARNs into GitHub variables.

After that, normal changes should flow through the controlled apply workflow.

## Safety Notes

- Do not commit `backend.hcl`, `terraform.tfvars`, `terraform.auto.tfvars`, `.terraform/`, or state files.
- Review the `lesson68-terraform-plan-dev` artifact before approving the GitHub Environment.
- Use `allow_destroy=ALLOW_DESTROY` only when the replacement/destroy action is intentional.
- The lab apply role uses broad permissions for training simplicity; production should use scoped permissions.
