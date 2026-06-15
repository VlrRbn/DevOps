# Lesson 71: Multi-Environment Promotion

This lesson turns the single-environment Terraform delivery model from lessons 68-70 into a promotion model across `dev`, `stage`, and `prod`.

The goal is one module contract, three root callers, separate state, separate approvals, and evidence at every promotion step.

## What Is Included

- `lesson.en.md` and `lesson.ru.md` - full lesson text
- `proof-pack.en.md` and `proof-pack.ru.md` - promotion evidence checklist
- `ci/lesson71-terraform-promote.yml` - GitHub Actions promotion template
- `policies/` - copied lesson 70 JSON plan policy gate
- `lab_71/terraform/envs/dev` - dev root module
- `lab_71/terraform/envs/stage` - stage root module
- `lab_71/terraform/envs/prod` - prod root module
- `lab_71/terraform/modules/network` - shared module used by all environments

## Environment Roots

Each environment has its own root directory:

```text
lab_71/terraform/envs/dev
lab_71/terraform/envs/stage
lab_71/terraform/envs/prod
```

Each root has:

- `main.tf`
- `variables.tf`
- `outputs.tf`
- `versions.tf`
- `backend.hcl.example`
- `terraform.tfvars.example`

## State Keys

Each environment must use a different state key:

```text
lab71/dev/full/terraform.tfstate
lab71/stage/full/terraform.tfstate
lab71/prod/full/terraform.tfstate
```

Same bucket is acceptable. Same key is not.

## Important OIDC Note

GitHub OIDC provider is account-level, not environment-level.

Do not let `dev`, `stage`, and `prod` all try to create the same provider in separate Terraform states. Use `github_oidc_provider_arn` for environments that should consume an existing provider.

## Bootstrap / First Run

The promotion workflow cannot create its own first IAM roles. It needs role ARNs before it can run:

- repository variables: `TF_PLAN_ROLE_ARN_DEV`, `TF_PLAN_ROLE_ARN_STAGE`, `TF_PLAN_ROLE_ARN_PROD`
- repository variables: `TF_APPLY_ROLE_ARN_DEV`, `TF_APPLY_ROLE_ARN_STAGE`, `TF_APPLY_ROLE_ARN_PROD`

First run options:

1. Use an admin/local profile to apply the first environment once, then copy role outputs into GitHub variables.
2. Use a separate account/bootstrap stack that owns GitHub OIDC and CI roles.

For production, prefer option 2. Environment stacks should consume the shared OIDC provider ARN and should not own account-level identity primitives.

## Operational Notes From Real Lab Failures

### Shared OIDC Provider ARN

If `github_oidc_provider_arn` is empty in more than one environment, Terraform may try to create the same GitHub OIDC provider again and fail with `EntityAlreadyExists`.

Correct model:

- create the account-level provider once;
- pass `github_oidc_provider_arn` to every environment that should consume it;
- if a provider is already tracked by the wrong environment state, use `terraform state rm` to remove ownership without deleting the AWS object.

### Required Tags Policy

The policy gate denies taggable resources that do not expose the required governance tags.

If the workflow fails with `deny_missing_required_tags`, fix the module by adding `tags = merge(local.tags, {...})` to resources that support tags. Do not use an allow-destroy exception for missing tags; exceptions are only for explicitly approved destructive changes.

## Quick Local Checks

From repo root:

```bash
terraform fmt -check -recursive lessons/71-multi-environment-promotion/lab_71/terraform
packer fmt -check -recursive lessons/71-multi-environment-promotion/lab_71/packer
lessons/71-multi-environment-promotion/policies/test-policy.sh
lessons/71-multi-environment-promotion/policies/test-opa.sh
```

Validate environment roots without remote backend:

```bash
for env in dev stage prod; do
  TF_DATA_DIR="/tmp/l71-${env}-data" \
  terraform -chdir="lessons/71-multi-environment-promotion/lab_71/terraform/envs/${env}" \
    init -backend=false -input=false -no-color

  TF_DATA_DIR="/tmp/l71-${env}-data" \
  terraform -chdir="lessons/71-multi-environment-promotion/lab_71/terraform/envs/${env}" \
    validate -no-color
done
```

Run module contract tests:

```bash
TF_DATA_DIR=/tmp/l71-module-test-data \
terraform -chdir=lessons/71-multi-environment-promotion/lab_71/terraform/modules/network \
  init -backend=false -input=false -no-color

TF_DATA_DIR=/tmp/l71-module-test-data \
terraform -chdir=lessons/71-multi-environment-promotion/lab_71/terraform/modules/network \
  test -no-color
```

## CI Template

`ci/lesson71-terraform-promote.yml` is a template. Copy it to `.github/workflows/lesson71-terraform-promote.yml`.

Workflow order:

1. choose `target_env`
2. provide promotion metadata: `release_id`, `source_env`, previous run URL, previous commit SHA
3. enforce the allowed path: `none -> dev`, `dev -> stage`, `stage -> prod`
4. for `stage/prod`, verify the previous GitHub Actions run through GitHub API
5. run fmt and native module tests
6. select the env-specific plan role
7. generate env-specific backend and tfvars
8. create saved plan and JSON plan
9. run policy gate, optionally with an explicit allow-destroy exception file
10. upload review artifacts and write GitHub Step Summary
11. approve GitHub Environment `terraform-${target_env}`
12. apply exact saved plan
13. run post-apply drift check

Required repository variables:

- `AWS_REGION`
- `TF_STATE_BUCKET`
- `TF_PLAN_ROLE_ARN_DEV`
- `TF_PLAN_ROLE_ARN_STAGE`
- `TF_PLAN_ROLE_ARN_PROD`
- `TF_APPLY_ROLE_ARN_DEV`
- `TF_APPLY_ROLE_ARN_STAGE`
- `TF_APPLY_ROLE_ARN_PROD`
- `TF_WEB_AMI_ID`
- `TF_SSM_PROXY_AMI_ID`
- `TF_GITHUB_OWNER`
- `TF_GITHUB_REPO`
- `TF_GITHUB_OIDC_PROVIDER_ARN`

GitHub Environments `terraform-dev`, `terraform-stage`, and `terraform-prod` are approval gates. They do not need to store role ARNs in this lesson version.

Role naming convention:

| Environment | AWS IAM role name | Terraform output | GitHub variable |
| --- | --- | --- | --- |
| `dev` | `lab71-dev-github-actions-plan-role` | `tf_plan_role_arn` | `TF_PLAN_ROLE_ARN_DEV` |
| `stage` | `lab71-stage-github-actions-plan-role` | `tf_plan_role_arn` | `TF_PLAN_ROLE_ARN_STAGE` |
| `prod` | `lab71-prod-github-actions-plan-role` | `tf_plan_role_arn` | `TF_PLAN_ROLE_ARN_PROD` |
| `dev` | `lab71-dev-github-actions-apply-role` | `tf_apply_role_arn` | `TF_APPLY_ROLE_ARN_DEV` |
| `stage` | `lab71-stage-github-actions-apply-role` | `tf_apply_role_arn` | `TF_APPLY_ROLE_ARN_STAGE` |
| `prod` | `lab71-prod-github-actions-apply-role` | `tf_apply_role_arn` | `TF_APPLY_ROLE_ARN_PROD` |

## Source Evidence Verification

For `stage` and `prod`, the workflow checks `source_workflow_run_url` with GitHub API.

The source run must:

- belong to the same repository
- be `completed` with `success`
- use the same commit SHA as the current promotion run
- belong to workflow `lesson71-terraform-promote`
- contain non-expired artifact `lesson71-<source_env>-apply`
- contain `promotion-manifest.json` with the same `release_id`, same commit SHA, same workflow run URL, `policy_decision=ALLOW`, and target env equal to the next run's `source_env`

## Provider Lock Files

This repo ignores `.terraform.lock.hcl` for ephemeral lesson labs because many lessons create short-lived root modules. In production, commit one lock file per root module so CI, local runs, and promotion pipelines use the same provider selections.

## Promotion Rule

Promotion is directional:

```text
dev -> stage -> prod
```

## Successful Promotion Chain

Happy path:

1. Run `target_env=dev`, `source_env=none`, `release_id=<id>`.
2. Save artifact `lesson71-dev-apply`, `apply-metadata.json`, and `promotion-manifest.json`.
3. Run `target_env=stage`, `source_env=dev`, same `release_id`, source URL from dev, source commit from dev.
4. Save artifact `lesson71-stage-apply`, `apply-metadata.json`, and `promotion-manifest.json`.
5. Run `target_env=prod`, `source_env=stage`, same `release_id`, source URL from stage, source commit from stage.
6. Save prod plan/apply artifacts, `apply-metadata.json`, `promotion-manifest.json`, and final proof pack.
