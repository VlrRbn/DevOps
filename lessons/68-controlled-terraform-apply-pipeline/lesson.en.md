# Lesson 68. Controlled Terraform Apply Pipeline

**Date:** 2026-06-01

**Focus:** build a manual, approval-gated Terraform `apply` workflow that applies only a fresh saved plan from `main`, uses OIDC, respects remote state locking, and captures post-apply evidence.

**Mindset:** `plan` is review. `apply` is release.

References:

- GitHub Actions deployments and environments: https://docs.github.com/en/actions/reference/deployments-and-environments
- Terraform saved plan/apply behavior: https://developer.hashicorp.com/terraform/cli/commands/apply
- Terraform plan `-out` behavior: https://developer.hashicorp.com/terraform/cli/commands/plan

---

## Why This Lesson Exists

Already built the one side of a safe Terraform delivery system:

- remote state and locking
- PR plan pipeline
- quality gates
- drift detection
- secret-safe inputs
- module contracts
- native module tests

One dangerous gap remains:

> Who is allowed to run `terraform apply`, from which source, with which plan, and how do we prove the result?

```text
Who actually has permission to change AWS?
Where is apply executed from?
Which exact plan is being applied?
Who approved it?
How can we later prove that the apply completed cleanly?
```

Bad pattern:

```text
push to main -> terraform apply -auto-approve
```

Why it is bad:

- any merge can immediately change AWS;
- the person may not see the final fresh plan;
- there is no proper approval;
- it is hard to prove exactly what was applied;
- destroy/replacement can happen too easily.

Better pattern:

```text
PR plan reviewed
  -> merge to main
  -> manual workflow_dispatch
  -> fresh saved plan from main
  -> upload plan artifact
  -> review plan artifact
  -> GitHub Environment approval
  -> apply exact saved plan artifact
  -> post-apply drift check
  -> artifacts and decision note
```

This lesson turns Terraform apply into a controlled release step.

---

## Outcomes

After this lesson you should be able to:

- explain why apply needs stronger controls than plan
- create a GitHub Environment gate for Terraform apply
- separate plan-role and apply-role trust models
- bind the apply role to a GitHub Environment OIDC subject
- run module native tests before apply
- generate a fresh saved plan from `main`
- apply exactly that saved plan
- block obvious destroy/replacement plans unless explicitly acknowledged
- run post-apply drift verification
- collect operational proof artifacts
- describe rollback as another controlled apply

---

## Quick Path

1. Bootstrap remote state if not already done.
2. Apply the lab once with a trusted local/admin path to create GitHub OIDC roles.
3. Copy `tf_plan_role_arn` into GitHub repository variable `TF_PLAN_ROLE_ARN`.
4. Copy `tf_apply_role_arn` into GitHub repository variable `TF_APPLY_ROLE_ARN`.
5. Create GitHub Environment `terraform-dev`.
6. Configure required reviewers for `terraform-dev`.
7. Add required repository variables.
8. Copy or use `.github/workflows/lesson68-terraform-apply-dev.yml`.
9. Trigger the workflow manually from `main` with `confirm_apply=APPLY`.
10. Review the plan artifact from `plan-dev`.
11. Approve the `terraform-dev` environment deployment for `apply-dev`.
12. Review apply artifacts and post-apply result.

---

## Prerequisites

- Lesson 60: remote state and native S3 lockfile.
- Lesson 63: PR plan pipeline.
- Lesson 64: drift detection.
- Lesson 67: Terraform native tests.
- A Terraform state bucket exists.
- Web and SSM proxy AMI IDs exist.
- You can create GitHub repository variables.
- You can create or use a GitHub Environment named `terraform-dev`.

---

## Repo Layout

```text
lessons/68-controlled-terraform-apply-pipeline/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── terraform-apply-dev.yml
└── lab_68/
    └── terraform/
        ├── backend-bootstrap/
        ├── envs/
        └── modules/network/
```

Active workflow path:

```text
.github/workflows/lesson68-terraform-apply-dev.yml
```

---

## A) Apply Delivery Model

A controlled apply pipeline has five gates.

| Gate | Purpose |
| --- | --- |
| Source gate | Apply only from `main` |
| Human gate | Require GitHub Environment approval |
| Identity gate | Use OIDC apply role, no static keys |
| Plan gate | Generate a fresh saved plan from current `main` |
| Verification gate | Run post-apply drift check and save evidence |

Rule:

> Do not apply a stale PR plan artifact blindly.

The PR plan is for review. The apply workflow creates a fresh plan after the change is merged because remote state, cloud reality, or `main` may have changed since the PR was opened.

Main Model:

```text
plan = review material
apply = controlled release
```

---

## B) Bootstrap Reality

There is one unavoidable problem:

> The apply workflow needs an AWS apply role, but Terraform creates that role.

So the first run cannot be fully self-service.

Recommended lab bootstrap:

1. Create or reuse the remote state bucket.
2. Run Terraform locally or from an already trusted admin path.
3. Create the GitHub OIDC provider and roles.
4. Capture outputs:
   - `tf_plan_role_arn`
   - `tf_apply_role_arn`
5. Store `tf_apply_role_arn` in GitHub variable `TF_APPLY_ROLE_ARN`.
6. Use controlled apply workflow for future changes.

CI/CD systems often need a bootstrap phase before they can manage themselves.

---

## C) GitHub Environment Gate

Create environment:

```text
terraform-dev
```

Configure if available:

- required reviewers
- prevent self-review
- deployment branch rule: `main`
- optional wait timer

Why this matters:

- the apply job pauses before it receives environment approval
- the approval is visible in the GitHub run
- environment-level variables/secrets can be separated from PR jobs
- the AWS role trust can bind to the environment subject

In this lab, the apply role trust policy expects this OIDC subject shape:

```text
repo:<owner>/<repo>:environment:terraform-dev
```

That means a normal PR job cannot assume the apply role unless it runs as a deployment to the approved environment.

---

## D) IAM Role Model

The lab now has two GitHub Actions roles.

| Role | Output | Trust model | Purpose |
| --- | --- | --- | --- |
| Plan role | `tf_plan_role_arn` | branch/PR subject | read/plan/backend checks |
| Apply role | `tf_apply_role_arn` | environment subject | approved Terraform apply |

The apply role is intentionally separate because apply has mutation power.

Lab simplification:

- `github_actions_apply_role` attaches `AdministratorAccess`.
- This is acceptable for a focused lab on pipeline controls.
- For real systems, replace it with a scoped policy and a separate break-glass runbook.

Rule:

> More power means narrower trust, stronger approval, and better evidence.

---

## E) Required GitHub Variables

Set repository variables:

| Variable | Example | Purpose |
| --- | --- | --- |
| `AWS_REGION` | `eu-west-1` | AWS region |
| `TF_STATE_BUCKET` | `vlrrbn-tfstate-...` | remote backend bucket |
| `TF_PLAN_ROLE_ARN` | `arn:aws:iam::...:role/lab68-github-actions-role` | OIDC plan role |
| `TF_APPLY_ROLE_ARN` | `arn:aws:iam::...:role/lab68-github-actions-apply-role` | OIDC apply role |
| `TF_WEB_AMI_ID` | `ami-...` | web launch template AMI |
| `TF_SSM_PROXY_AMI_ID` | `ami-...` | SSM proxy AMI |

The workflow writes `backend.hcl` and `terraform.auto.tfvars` at runtime. It does not rely on committed `terraform.tfvars`.

This is important because `terraform.tfvars` is intentionally ignored.

---

## F) Workflow Design

Workflow file:

```text
.github/workflows/lesson68-terraform-apply-dev.yml
```

Template copy:

```text
lessons/68-controlled-terraform-apply-pipeline/ci/terraform-apply-dev.yml
```

Core controls:

- `workflow_dispatch` only
- explicit guard step fails unless `confirm_apply=APPLY`
- explicit guard step fails unless the run is from `main`
- `plan-dev` runs without GitHub Environment approval
- `plan-dev` runs fmt and native tests before AWS credentials
- `plan-dev` assumes the lower-power plan role
- `plan-dev` creates `tfplan`, `tfplan.txt`, and `tfplan.json`
- `plan-dev` uploads `lesson68-terraform-plan-dev` for human review
- `apply-dev` waits on GitHub Environment `terraform-dev` approval
- `apply-dev` assumes the environment-scoped apply role
- `apply-dev` downloads and applies exactly the saved `tfplan` artifact
- destroy/replacement is detected from JSON plan data with `jq`
- post-apply verification runs `terraform plan -detailed-exitcode`
- both jobs upload short-lived operational artifacts

Important distinction:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

This means apply uses the exact saved plan. It does not silently recalculate a different plan during apply.

---

## G) Destroy Guard

The workflow uses the JSON plan, not grepping the human-readable text:

```bash
terraform show -json tfplan > tfplan.json
jq '[.resource_changes[]? | select(.change.actions | index("delete"))]' tfplan.json
```

This catches both direct destroy and replacement because Terraform replacement includes a delete action.

This is still a learning guardrail, not a complete policy engine.

It blocks unless the operator explicitly re-runs with:

```text
allow_destroy=ALLOW_DESTROY
```

In production, add stronger policy gates:

- OPA/Conftest
- Sentinel
- Checkov policy
- parsed JSON plan checks with allowed action lists
- explicit change windows
- separate break-glass workflow

Lab rule:

> If destroy/replacement appears, stop and explain before applying.

---

## H) Post-Apply Verification

After apply, run:

```bash
terraform plan -detailed-exitcode
```

Exit codes:

| Code | Meaning | Pipeline action |
| --- | --- | --- |
| `0` | no diff | success |
| `1` | error | fail |
| `2` | diff remains | fail and inspect |

Why this matters:

- apply can succeed but leave residual drift/diff
- provider defaults can change state shape
- external systems can modify resources during apply
- a clean post-apply plan is strong evidence

This is not a full runtime smoke test. It proves Terraform state and config agree after apply.

---

## I) Artifact Discipline

The lesson has two artifacts:

```text
lesson68-terraform-plan-dev
lesson68-terraform-apply-dev
```

`lesson68-terraform-plan-dev` is needed before approval:

```text
plan.txt                      -> output of the terraform plan command
tfplan.txt                    -> saved plan in human-readable form
tfplan.json                   -> machine checks / policy
tfplan                        -> binary plan for apply
destructive_changes.json      -> list of resources with delete/replacement actions
destructive-summary.txt       -> short summary of destructive_count
```

`lesson68-terraform-apply-dev` is needed after apply:

```text
plan.txt
tfplan.txt
tfplan.json
destructive_changes.json
destructive-summary.txt
apply.txt                     -> what actually happened during apply
post_apply_plan.txt           -> verification after apply
post_apply_exitcode.txt       -> 0/1/2 verification result
```

Treat artifacts as operational data.

They can include:

- resource names
- ARNs
- security group IDs
- subnet IDs
- tags
- AMI IDs
- IAM role names

Retention is short: `7` days.

The proof pack must answer:

- Which run?
- Which commit SHA?
- Who approved it?
- Which plan was used?
- Was there any destroy?
- What was applied?
- Is the post-apply plan clean?
- Is rollback needed?

---

## J) Rollback Model

This lesson does not implement auto rollback.

Rollback is still an apply.

### Option 1 - Revert commit and apply

Use when the change was code-based and the revert is clear.

```text
git revert <bad commit>
open PR
review plan
merge
manual apply
post-apply verify
```

### Option 2 - Fix forward

Use when revert is riskier than a small corrective change.

For example:

- the resource has already been recreated;
- the old state cannot be restored safely;
- rollback would break a new dependency;
- it is easier to fix the parameter and apply again.


### Option 3 - Break-glass runbook

Use only when:

- CI is broken;
- infrastructure is degraded;
- delay is worse than controlled manual action;
- manual emergency action is required.

Break-glass still needs evidence after the fact.

```text
what was done
who did it
when
why
how it was brought back under Terraform control
```

---

## Final Lesson Model

```text
source gate:
  main only

manual gate:
  workflow_dispatch + confirm_apply=APPLY

quality gate:
  fmt + terraform test

identity gate:
  plan role for plan-dev
  apply role for apply-dev
  OIDC without static AWS keys

plan gate:
  fresh terraform plan -out=tfplan from main

review gate:
  plan artifact before approval

human gate:
  GitHub Environment terraform-dev

safety gate:
  JSON destroy/replacement guard

apply gate:
  terraform apply exact saved tfplan

verification gate:
  post-apply terraform plan -detailed-exitcode

evidence gate:
  artifacts + decision note
```

---

## K) Drills

### Drill 1 - Safe tag apply

Change a harmless tag or alarm description.

Expected:

- PR plan shows the change
- merge to `main`
- manual apply workflow waits for environment approval
- apply succeeds
- post-apply exit code is `0`

### Drill 2 - Confirm guard

Run workflow with:

```text
confirm_apply = NO
```

Expected:

- apply job does not run

### Drill 3 - Environment approval

Run workflow with valid inputs.

Expected:

- job pauses at `terraform-dev`
- reviewer approves
- apply continues

### Drill 4 - Destroy guard

Create a change that would destroy or replace a safe lab resource.

Expected:

- workflow stops before apply unless `allow_destroy=ALLOW_DESTROY`
- artifact shows the risky plan

### Drill 5 - Post-apply proof

After apply completes, inspect:

```text
post_apply_exitcode.txt
post_apply_plan.txt
```

Expected:

- exit code `0`
- no residual diff

---

## L) Proof Pack

Capture:

```text
evidence/
  apply-run-url.txt
  environment-approval-note.md
  repository-vars-redacted.md
  plan.txt
  tfplan.txt
  apply.txt
  post_apply_plan.txt
  post_apply_exitcode.txt
  decision.txt
```

`decision.txt` should answer:

```markdown
# Apply Decision

- Source branch:
- Commit SHA:
- Environment:
- Reviewer:
- Expected change:
- Destroy/replacement present: yes/no
- allow_destroy used: yes/no
- Applied saved plan: yes/no
- Post-apply plan clean: yes/no
- Rollback needed: yes/no
```

---

## Common Pitfalls

- automatic apply on every push to main too early
- same IAM role for PR plan and apply
- applying stale PR plan artifacts
- relying on ignored local `terraform.tfvars` in CI
- no GitHub Environment approval
- OIDC trust not bound to environment
- canceling an in-progress apply
- treating JSON destroy guard as a complete policy engine
- uploading artifacts without thinking about sensitivity
- skipping post-apply drift check

---

## Security Checklist

- OIDC only, no static AWS keys
- apply role separate from plan role
- apply role bound to GitHub Environment subject
- apply workflow runs only from `main`
- apply workflow is `workflow_dispatch`
- `confirm_apply=APPLY` required
- GitHub Environment approval required
- remote backend uses native S3 lockfile
- saved plan is applied
- destroy/replacement requires explicit acknowledgment
- post-apply drift check required
- artifacts have short retention

---

## Final Acceptance

Lesson 68 is complete if:

- [ ] `terraform-dev` environment exists
- [ ] plan role ARN is stored in `TF_PLAN_ROLE_ARN`
- [ ] apply role ARN is stored in `TF_APPLY_ROLE_ARN`
- [ ] required GitHub variables are configured
- [ ] workflow runs only from `main`
- [ ] environment approval is required
- [ ] native tests run before apply
- [ ] saved plan is generated and applied
- [ ] destroy guard blocks risky changes by default
- [ ] post-apply plan returns exit code `0`
- [ ] proof pack is captured
- [ ] rollback decision is documented if needed

---

## Lesson Summary

- **What you learned:** Terraform apply should be a controlled release, not generic CI.
- **What you practiced:** GitHub Environment approval, OIDC apply role, saved plan apply, destroy guard, post-apply drift check.
- **Operational focus:** apply only after source, human, identity, plan, and verification gates pass.
- **Why it matters:** the safest plan pipeline still fails operationally if apply is uncontrolled.
