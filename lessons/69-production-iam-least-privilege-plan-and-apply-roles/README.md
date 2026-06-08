# Lesson 69 - Production IAM Least Privilege for Terraform

This lesson continues lesson 68. The controlled apply pipeline is already in place; this lesson tightens the Terraform roles used by that pipeline.

## Goal

Replace broad managed permissions with scoped plan/apply roles:

- plan role can read state, lock state, and refresh resources
- plan role cannot mutate infrastructure
- apply role can mutate only the lab stack service areas
- apply role can pass only approved EC2 runtime role
- apply role is still protected by GitHub Environment OIDC trust
- break-glass remains separate from normal delivery

## Files

- `lesson.en.md` - English lesson
- `lesson.ru.md` - Russian lesson
- `proof-pack.en.md` - evidence checklist in English
- `proof-pack.ru.md` - evidence checklist in Russian
- `lab_69/terraform/modules/network/iam.tf` - scoped plan/apply IAM implementation
- `lab_69/terraform/modules/network/tests/` - native Terraform contract tests
- `lab_69/packer/` - AMI builders copied forward for the lab

## Main Change From Lesson 68

Lesson 68 used this lab shortcut:

```text
apply role -> AdministratorAccess
```

Lesson 69 replaces it with:

```text
plan role  -> backend lockfile + read/refresh policy
apply role -> backend lockfile + scoped lab mutate policy + restricted iam:PassRole
```

## Workflow Template

Lesson 69 keeps the controlled apply shape from lesson 68 but provides a retargeted template:

```text
lessons/69-production-iam-least-privilege-plan-and-apply-roles/ci/lesson69-terraform-apply-dev.yml
```

If you want to run lesson 69 through GitHub Actions, copy it to:

```text
.github/workflows/lesson69-terraform-apply-dev.yml
```

The template uses:

```text
TF_ROOT: lessons/69-production-iam-least-privilege-plan-and-apply-roles/lab_69/terraform
state key: lab69/dev/full/terraform.tfstate
project_name: lab69
secret paths: /devops/lab69/...
```

After bootstrapping lab 69, update GitHub repository variables to the lab 69 role ARNs:

```text
TF_PLAN_ROLE_ARN  -> lab69-github-actions-role
TF_APPLY_ROLE_ARN -> lab69-github-actions-apply-role
TF_STATE_BUCKET   -> existing state bucket
```

Do not point the lesson 68 workflow at lab69 role ARNs unless you also retarget paths, backend key, project name, and secret/parameter names.

## Validation

From repo root:

```bash
terraform fmt -check -recursive lessons/69-production-iam-least-privilege-plan-and-apply-roles/lab_69/terraform

TF_DATA_DIR=/tmp/l69-module-test-data \
AWS_EC2_METADATA_DISABLED=true \
terraform -chdir=lessons/69-production-iam-least-privilege-plan-and-apply-roles/lab_69/terraform/modules/network init -backend=false -input=false -no-color

TF_DATA_DIR=/tmp/l69-module-test-data \
AWS_EC2_METADATA_DISABLED=true \
terraform -chdir=lessons/69-production-iam-least-privilege-plan-and-apply-roles/lab_69/terraform/modules/network test -no-color
```

## Safety Notes

- This is a scoped lab policy, not a universal production policy.
- Some AWS actions still need `Resource = "*"`; document those instead of pretending they are tightly scoped.
- Do not use the Terraform apply role as break-glass admin.
- Keep proof artifacts redacted before committing them publicly.
