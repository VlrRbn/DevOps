# Lesson 71 Proof Pack

Use this checklist for multi-environment promotion evidence.

Recommended ignored folder:

```text
lessons/71-multi-environment-promotion/evidence/l71-YYYYmmdd_HHMMSS/
```

## 1. Environment Matrix

Save a short matrix:

```text
env=dev   state_key=lab71/dev/full/terraform.tfstate   github_environment=terraform-dev
env=stage state_key=lab71/stage/full/terraform.tfstate github_environment=terraform-stage
env=prod  state_key=lab71/prod/full/terraform.tfstate  github_environment=terraform-prod
```

## 2. Promotion Metadata

For each promotion step, save:

```text
release_id=<release/change id>
source_env=none|dev|stage
target_env=dev|stage|prod
source_workflow_run_url=<required for stage/prod>
source_commit_sha=<required for stage/prod>
target_commit_sha=<current workflow commit>
```

For `stage` and `prod`, `source_commit_sha` must match the current workflow run commit.
The workflow also verifies the source run through GitHub API and expects artifact `lesson71-<source_env>-apply`.

## 3. Per-Environment Plan Evidence

For each promoted environment, save:

- `plan.txt`
- `tfplan.txt`
- `tfplan.json`
- `policy-results/policy-decision.txt`
- `policy-results/policy-deny.json`
- `policy-results/policy-warn.json`
- GitHub Step Summary
- verified source run URL for `stage/prod`
- artifact name: `lesson71-<env>-plan`

## 4. Apply Evidence

For each applied environment, save:

- `apply.txt`
- `apply-metadata.json`
- `post_apply_plan.txt`
- `post_apply_exitcode.txt`
- `promotion-manifest.json`, if post-apply drift check passed
- workflow run URL
- artifact name: `lesson71-<env>-apply`
- GitHub Environment approval note or screenshot

## 5. Promotion Decision

Create `promotion-decision.txt`:

```text
PROMOTION=none->dev|dev->stage|stage->prod
release_id=<release/change id>
source_env=<env>
target_env=<env>
decision=GO|NO-GO
reason=<short reason>
reviewer=<name or handle>
timestamp=<UTC timestamp>
```

## 6. Isolation Proof

Save evidence that:

- backend key matches target env
- root output `environment` matches target env
- root output `project_name` matches target env
- plan role matches target env
- apply role matches target env through `TF_APPLY_ROLE_ARN_DEV/STAGE/PROD`
- policy artifacts belong to the same target env
- apply artifact uses the exact saved plan from the plan job
- `promotion-manifest.json` contains the same `release_id`, commit SHA, workflow run URL, and `policy_decision=ALLOW`

## 7. Redaction Checklist

Before sharing or committing evidence, check for:

- AWS account IDs
- role ARNs
- state bucket name, if private
- instance IDs
- public IPs
- secret values
- full `tfplan.json` contents from sensitive resources

## 8. Real Failure Notes

If these errors happened during the lab, save a short note with the cause and fix:

- `EntityAlreadyExists` for the GitHub OIDC provider: an environment tried to create the account-level provider again; fix by passing `github_oidc_provider_arn` or removing provider ownership from state with `terraform state rm` without deleting it from AWS.
- `deny_missing_required_tags`: the policy gate found taggable resources without required tags; fix the module by adding `local.tags`, not by bypassing policy with an exception file.
