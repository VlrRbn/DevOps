# Lesson 71. Multi-Environment Promotion: dev -> stage -> prod

**Date:** 2026-06-08

**Focus:** promote one Terraform module contract across multiple environments without copy-paste drift.

**Main idea:** environments are separate deployments of the same contract, not separate hand-edited codebases.

---

## Why This Lesson Exists

Lessons 68-70 was built a controlled Terraform delivery path for one environment:

```text
controlled apply -> least-privilege IAM -> JSON plan policy
```

Lesson 71 adds the production delivery shape:

```text
dev -> stage -> prod
```

What you must not do

Bad model:

- copied `dev`
- manually renamed it to `stage`
- copied it again to `prod`
- changed `CIDR` somewhere
- changed `desired_capacity` somewhere
- forgot to update `IAM` somewhere
- changed the `module` somewhere

After a couple of weeks, these are no longer three environments. They are three different infrastructures that only look similar.

The goal is not three copies of the same Terraform code. The goal is:

- one shared module
- three root callers
- three state keys
- three approval levels
- one policy model
- promotion evidence at each step

---

## Outcomes

After this lesson you should be able to:

- split one Terraform lab into `dev`, `stage`, and `prod` roots
- keep one shared `modules/network` implementation
- use separate backend keys per environment
- tune environment inputs without editing module internals
- understand why GitHub OIDC provider is a shared account-level object
- run the same plan/policy/apply discipline per environment
- capture promotion evidence for `dev -> stage` and `stage -> prod`

---

## Repo Layout

```text
lessons/71-multi-environment-promotion/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── lesson71-terraform-promote.yml
├── policies/
│   ├── terraform-plan-policy.sh
│   ├── test-policy.sh
│   └── test-opa.sh
└── lab_71/
    ├── packer/
    └── terraform/
        ├── envs/
        │   ├── dev/
        │   ├── stage/
        │   └── prod/
        └── modules/network/
```

---

## A) Environment Model

Each environment has a separate root directory:

```text
lab_71/terraform/envs/dev
lab_71/terraform/envs/stage
lab_71/terraform/envs/prod
```

Each root has the same shape:

- `main.tf`
- `variables.tf`
- `outputs.tf`
- `versions.tf`
- `backend.hcl.example`
- `terraform.tfvars.example`

Each environment calls the same `modules/network`:

The shared module stays here:

```text
module "network" {
  source = "../../modules/network"
}
```

But it passes different values:

```text
dev   -> small size, low criticality
stage -> closer to prod, medium criticality
prod  -> stricter, high criticality
```

Key idea:

`dev`, `stage`, and `prod` are not three copies of code. They are three different calls to the same contract.

The contract is the `module interface`:

```text
variables
outputs
validation
preconditions
IAM expectations
state expectations
```

Rule:

```text
If you need to change environment behavior, first change the root module inputs.

If you need to change the contract itself, then change the shared module, and the change must move through:

dev -> stage -> prod
```

Why this matters:

Imagine you are changing the ASG rolling update strategy.

Bad option:

```text
changed asg.tf in dev
forgot to change it in stage
copied the old version to prod
```

Correct option:

```text
changed modules/network/asg.tf once
tested it in dev
then promoted the same commit to stage
then promoted the same commit to prod
```

This way, you know that `prod` received exactly the same change that already passed through `dev` and `stage`.

`Promotion` is the provable movement of one release candidate:

```text
same code
same commit
same release_id
same module contract
separate env inputs
stronger approvals near prod
```

---

## B) State Isolation

Each environment must have a unique state key:

```text
lab71/dev/full/terraform.tfstate
lab71/stage/full/terraform.tfstate
lab71/prod/full/terraform.tfstate
```

Same S3 bucket is acceptable. Same state key is not.

Why?

`Terraform state` is a resource ownership map.

It stores roughly this kind of information:

```text
aws_vpc.main -> vpc-...
aws_subnet.public["a"] -> subnet-...
aws_autoscaling_group.web -> lab71-dev-web-asg
```

If `dev` and `prod` accidentally point to the same `state`, Terraform starts thinking that they manage the same resources.

What can happen:

- you run `dev apply`
- Terraform reads `prod state`
- it sees `prod resources`
- it tries to bring them to `dev inputs`

In this lesson, explicit directories are used instead of `Terraform CLI workspaces`, because this is easier to understand for CI and change review.

When a reviewer looks at a `PR` or an `artifact`, they immediately see:

```text
target_env=stage
backend_key=lab71/stage/full/terraform.tfstate
GitHub Environment=terraform-stage
```

The root variables now have `validation`:

```hcl
variable "environment" {
  validation {
    condition = var.environment == "stage"
  }
}

variable "tf_state_key" {
  validation {
    condition = var.tf_state_key == "lab71/stage/full/terraform.tfstate"
  }
}
```

This protects against manual mistakes.

Why there are two checks:

- `backend.hcl` is needed by the Terraform backend itself: `key = "lab71/stage/full/terraform.tfstate"`
- `tf_state_key` inside variables is needed for the IAM policy: `tf_state_key = "lab71/stage/full/terraform.tfstate"`
- this is because the `plan/apply role` must have access only to its own `state object` and `lockfile`
- if the `backend key` and the `IAM policy key` do not match, you will get confusing errors

---

## C) Environment Inputs

The module source is the same.

Shared `module`:

```text
lab_71/terraform/modules/network
```

Inputs differ.

```text
lab_71/terraform/envs/dev
lab_71/terraform/envs/stage
lab_71/terraform/envs/prod
```

| Env | Project | CIDR | Size | GitHub Environment |
| --- | --- | --- | --- | --- |
| dev | `lab71-dev` | `10.71.0.0/16` | 1-2 instances | `terraform-dev` |
| stage | `lab71-stage` | `10.72.0.0/16` | 2-3 instances | `terraform-stage` |
| prod | `lab71-prod` | `10.73.0.0/16` | 2-4 instances | `terraform-prod` |

Purpose of `dev`: cheaper, fewer instances, lower criticality, simpler approval, faster change validation.

Purpose of `stage`: closer to `prod`, validates behavior with multiple instances, requires a reviewer, catches problems before `prod`.

Purpose of `prod`: stricter, larger `blast radius`, stronger approval, less debug access.

Examples live in:

```text
envs/dev/terraform.tfvars.example
envs/stage/terraform.tfvars.example
envs/prod/terraform.tfvars.example
```

Real values belong in ignored local tfvars or CI variables, not committed secrets.

---

## D) Shared OIDC Provider Trap

GitHub OIDC provider is account-level.

Do not create it independently in `dev`, `stage`, and `prod` states. The second environment can fail because the provider URL already exists in the AWS account.

AWS will say something like: `EntityAlreadyExists`.

Use this when an account-level provider already exists.

Operational rule:

```text
Bootstrap shared account objects once. Environment states should consume them by ARN.

github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
```

In the `module`, this is implemented like this:

```hcl
resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.github_oidc_provider_arn == "" ? 1 : 0
}
```

* if the `ARN` is empty: `create provider`
* if the `ARN` is provided: `use existing provider`

The `OIDC provider` is a shared door from GitHub into the AWS account.

If environments own this door, there is a risk:

```text
dev state can accidentally delete the shared provider
stage/prod apply roles depend on an object owned by dev
ownership becomes unclear
```

The `apply policy` no longer allows:

```text
iam:CreateOpenIDConnectProvider
iam:DeleteOpenIDConnectProvider
iam:TagOpenIDConnectProvider
```

Environment apply roles should not create or delete the shared GitHub OIDC provider. In this lab the apply policy manages environment-scoped roles and instance profiles, but the shared OIDC provider belongs to bootstrap/account setup.

---

## D1) Operational Notes From This Lab

This lab produced two useful failures. They are worth keeping in the lesson because they look like real production issues.

### 1. Empty or Wrong `github_oidc_provider_arn`

Symptom:

```text
EntityAlreadyExists: Provider with url https://token.actions.githubusercontent.com already exists
```

Cause:

- The GitHub OIDC provider already exists in the AWS account.
- `github_oidc_provider_arn` is empty or wrong for the environment.
- Terraform sees `count = 1` and tries to create the provider again.

Correct fix:

```hcl
github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
```

If the provider is already tracked in one environment state but should now be treated as a shared bootstrap object, remove it from that state without deleting it from AWS:

```bash
terraform state rm 'module.network.aws_iam_openid_connect_provider.github_actions[0]'
```

This does not delete the provider in AWS. It only tells the current state: “this shared object is no longer owned by this environment”.

### 2. Policy Gate Failed Because Tags Were Missing

Symptom:

```text
POLICY_DECISION=DENY
rule=deny_missing_required_tags
```

Cause:

- The lesson 70 policy checks required tags.
- Some resources were created without `local.tags`.
- For promotion, this is correct behavior: if policy requires tags, the module must consistently tag taggable resources.

Fix:

- add `tags = merge(local.tags, {...})` to resources that support tags;
- do not bypass policy with an exception file;
- keep exceptions only for explicitly approved destructive changes.

Takeaway:

```text
A policy failure is not always a policy problem.
Often it means the module contract is not meeting governance requirements.
```

---

## E) Bootstrap / First Run

The CI promotion workflow needs IAM role ARNs before it can plan or apply:

- `TF_PLAN_ROLE_ARN_DEV`
- `TF_PLAN_ROLE_ARN_STAGE`
- `TF_PLAN_ROLE_ARN_PROD`
- `TF_APPLY_ROLE_ARN_DEV`
- `TF_APPLY_ROLE_ARN_STAGE`
- `TF_APPLY_ROLE_ARN_PROD`

Those ARNs cannot appear from a workflow that has no credentials yet.

Valid first-run paths:

1. Local/admin bootstrap: apply the first environment once with an admin profile, then copy outputs into GitHub variables/environments.
2. Separate account bootstrap stack: create GitHub OIDC and CI roles outside env states, then pass `github_oidc_provider_arn` into every env.

In a real project, `CI roles` and the `OIDC provider` should be moved into a separate `bootstrap / account stack`.

But for now, we use option 1: local/admin `bootstrap`.

For each environment:

```text
cd lessons/71-multi-environment-promotion/lab_71/terraform/envs/dev
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

Fill in the real values:

```text
web_ami_id = "ami-..."
ssm_proxy_ami_id = "ami-..."
github_owner = "VlrRbn"
github_repo = "DevOps"
github_oidc_provider_arn = "arn:aws:iam::...:oidc-provider/token.actions.githubusercontent.com"
tf_state_bucket_name = "..."
```

Then run:

```text
terraform init -reconfigure -backend-config=backend.hcl
terraform apply

terraform output tf_plan_role_arn
terraform output tf_apply_role_arn
```

Role output mapping:

| Environment | AWS IAM role name | Output | GitHub variable |
| --- | --- | --- | --- |
| `dev` | `lab71-dev-github-actions-plan-role` | `tf_plan_role_arn` | `TF_PLAN_ROLE_ARN_DEV` |
| `stage` | `lab71-stage-github-actions-plan-role` | `tf_plan_role_arn` | `TF_PLAN_ROLE_ARN_STAGE` |
| `prod` | `lab71-prod-github-actions-plan-role` | `tf_plan_role_arn` | `TF_PLAN_ROLE_ARN_PROD` |
| `dev` | `lab71-dev-github-actions-apply-role` | `tf_apply_role_arn` | `TF_APPLY_ROLE_ARN_DEV` |
| `stage` | `lab71-stage-github-actions-apply-role` | `tf_apply_role_arn` | `TF_APPLY_ROLE_ARN_STAGE` |
| `prod` | `lab71-prod-github-actions-apply-role` | `tf_apply_role_arn` | `TF_APPLY_ROLE_ARN_PROD` |

---

## F) Local Validation

From repo root:

```bash
terraform fmt -check -recursive lessons/71-multi-environment-promotion/lab_71/terraform
packer fmt -check -recursive lessons/71-multi-environment-promotion/lab_71/packer
lessons/71-multi-environment-promotion/policies/test-policy.sh
lessons/71-multi-environment-promotion/policies/test-opa.sh
```

What it checks:

- Terraform files are formatted
- Packer HCL files are formatted
- `policy tests` passed
- `OPA policy tests` passed

Check that the `root module` and the `module interface` match:

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

These tests verify the `module contract`:

```text
bad AMI ID fails
single private subnet fails
bad state key fails
empty tag value fails
reserved tag override fails
outputs remain stable
IAM policy does not receive broad permissions
PassRole is limited to the EC2 runtime role
```


---

## G) Promotion Workflow

The workflow template lives here:

```text
ci/lesson71-terraform-promote.yml
```

When it is ready to run, copy it to:

```text
.github/workflows/lesson71-terraform-promote.yml
```

### Workflow Inputs

- `target_env`: where the change is applied: `dev`, `stage`, or `prod`.
- `source_env`: where the change is promoted from: `none`, `dev`, or `stage`.
- `release_id`: stable release or change request identifier.
- `source_workflow_run_url`: required for `stage` and `prod`.
- `source_commit_sha`: required for `stage` and `prod`; must match the current commit.
- `allow_destroy_exception_path`: optional repo-relative JSON exception file for approved destructive changes.
- `confirm_apply`: must be exactly `APPLY`.

Only these transitions are allowed:

```text
none  -> dev
dev   -> stage
stage -> prod
```

These transitions are not allowed:

```text
none  -> prod
dev   -> prod
stage -> dev
```

One `release_id` should move through the whole chain:

```text
dev   release_id=rel-l71-001
stage release_id=rel-l71-001
prod  release_id=rel-l71-001
```

For `dev`, no previous run is needed:

```text
source_env=none
```

For `stage`, provide the successful dev run URL:

```text
source_workflow_run_url=https://github.com/.../actions/runs/123
```

For `prod`, provide the successful stage run URL.

`source_commit_sha` proves this:

```text
stage/prod promote the same code that already passed the previous environment
```

If the commit is different, the workflow fails.

Apply does not start immediately after plan. GitHub Environment approval sits between them.

That protects against accidental runs and against applying a plan nobody reviewed.

### Guard Step

First, the workflow checks:

```text
confirm_apply == APPLY
release_id is not empty
branch == main
target_env is valid
source_env is valid
promotion path is valid
stage/prod have source URL and source SHA
source SHA == current GITHUB_SHA
```

If anything is wrong, the workflow fails before AWS credentials are requested.

That matters:

```text
an invalid request should not even receive AWS OIDC credentials
```

### Previous Promotion Evidence Check

For `stage` and `prod`, the workflow verifies the previous run through GitHub API.

It checks:

```text
URL points to the same repository
run completed + success
workflow name == lesson71-terraform-promote
head_sha == source_commit_sha
head_sha == current GITHUB_SHA
artifact lesson71-<source_env>-apply exists and is not expired
```

Then it downloads the artifact:

```text
lesson71-dev-apply
```

or:

```text
lesson71-stage-apply
```

Inside, it expects:

```text
promotion-manifest.json
```

The manifest must contain:

```text
same release_id
target_env == source_env
commit_sha == current GITHUB_SHA
policy_decision == ALLOW
tfplan_sha256 not empty
workflow_run_url == source_workflow_run_url
```

Without the manifest, you could accidentally use “some successful dev run”.

With the manifest, the workflow proves:

```text
this is the same release
this is the same commit
this is the previous environment
policy was ALLOW
the artifact belongs to the URL entered by the operator
```

### Plan Job

After the guard and previous-run check, the workflow does this:

```text
terraform fmt
terraform test
select plan role
configure AWS credentials via OIDC
write backend.hcl
write terraform.auto.tfvars
terraform init
terraform validate
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
policy check
upload plan artifact
```

The plan role is selected by environment:

```text
dev   -> TF_PLAN_ROLE_ARN_DEV
stage -> TF_PLAN_ROLE_ARN_STAGE
prod  -> TF_PLAN_ROLE_ARN_PROD
```

### Apply Job

The apply job depends on plan:

```yaml
needs: plan
```

It is also attached to a GitHub Environment:

```yaml
environment:
  name: terraform-${{ github.event.inputs.target_env }}
```

So:

```text
target_env=prod -> GitHub Environment terraform-prod
```

GitHub waits for approval there.

After approval, the workflow does this:

```text
select TF_APPLY_ROLE_ARN_DEV/STAGE/PROD by target_env
configure AWS credentials via selected apply role ARN
download exact plan artifact
terraform init
terraform apply tfplan
post-apply drift check
write apply-metadata.json
write promotion-manifest.json
upload apply artifact
```

### Why The Exact Saved Plan Matters

Apply uses:

```bash
terraform apply tfplan
```

Not:

```bash
terraform apply
```

Bad flow:

```text
plan showed one thing
approval was given
apply created a new plan
apply changed something else
```

Correct flow:

```text
reviewer inspected tfplan
approval was given for tfplan
apply applied exactly that tfplan
```

### Artifacts

Plan artifact:

```text
lesson71-<env>-plan
```

Contains:

```text
tfplan
tfplan.txt
tfplan.json
plan.txt
terraform.auto.tfvars
policy-results/
```

Apply artifact:

```text
lesson71-<env>-apply
```

Contains:

```text
apply.txt
apply-metadata.json
post_apply_plan.txt
post_apply_exitcode.txt
promotion-manifest.json
```

`apply-metadata.json` is written immediately after apply with `if: always()`.

Purpose:

```text
even if the drift check fails later, metadata about the apply attempt remains
```

`promotion-manifest.json` is written only after a successful post-apply drift check.

Purpose:

```text
only a clean environment can be promoted further
```

If the drift check fails, the manifest is not created. That means `stage` or `prod` cannot use that run as promotion source.

### Short Workflow Order

1. Validate inputs, branch, release id, and promotion path.
2. Allow only `none -> dev`, `dev -> stage`, `stage -> prod`.
3. For `stage/prod`, verify the previous GitHub Actions run through GitHub API.
4. Run Terraform fmt.
5. Run native module tests.
6. Select the plan role for the target environment.
7. Generate backend and tfvars for the target environment.
8. Run init/validate.
9. Create saved plan.
10. Convert plan to JSON.
11. Run the lesson 70 policy gate.
12. Upload plan artifacts and write GitHub Step Summary.
13. Wait for GitHub Environment approval.
14. Assume the apply role for the target environment.
15. Apply the exact saved plan.
16. Run post-apply drift check.

For `stage` and `prod`, the previous run must be a successful completed run of workflow `lesson71-terraform-promote` from the same repository, on the same commit, with a non-expired artifact `lesson71-<source_env>-apply`.

Inside the artifact, `promotion-manifest.json` must contain the same `release_id`, the same commit, `policy_decision=ALLOW`, and the same `workflow_run_url` that was passed as `source_workflow_run_url`.

---

## H) GitHub Variables And Environments

Repository variables:

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

GitHub Environments:

- `terraform-dev`
- `terraform-stage`
- `terraform-prod`

GitHub Environments are approval gates in this workflow. Role ARNs are repository variables with explicit env suffixes.

Suggested protection:

| Environment | Protection |
| --- | --- |
| `terraform-dev` | light approval |
| `terraform-stage` | required reviewer |
| `terraform-prod` | required reviewer + branch restriction + optional wait timer |

---

## I) Promotion Rules

1. Dev first: `source_env=none`, `target_env=dev`.
2. Stage only after dev: `source_env=dev`, `target_env=stage`.
3. Prod only after stage: `source_env=stage`, `target_env=prod`.
4. Same module source across all environments.
5. Same AMI/build when promoting a release candidate.
6. Separate state keys always.
7. Plan role is environment-scoped.
8. Prod requires stronger approval.
9. Apply uses exact saved plan artifact.
10. Every promotion has evidence: release id, source run URL, source commit, policy decision, artifacts.

Provider lock note: this training repo ignores `.terraform.lock.hcl` for ephemeral lesson roots. In production, commit lock files per root module.

Promotion is not “copy dev and tweak prod by hand”.

Promotion is “same contract, controlled inputs, stronger gates”.

---

## J) Drills

### Drill 1. Prove Root Isolation

Check backend examples:

```bash
for env in dev stage prod; do
  echo "--- $env"
  cat lessons/71-multi-environment-promotion/lab_71/terraform/envs/$env/backend.hcl.example
  grep "lab71/${env}/full/terraform.tfstate" \
    lessons/71-multi-environment-promotion/lab_71/terraform/envs/$env/backend.hcl.example
done
```

### Drill 2. Validate All Roots

```bash
for env in dev stage prod; do
  TF_DATA_DIR="/tmp/l71-${env}-data" terraform \
    -chdir="lessons/71-multi-environment-promotion/lab_71/terraform/envs/${env}" \
    init -backend=false -input=false -no-color

  TF_DATA_DIR="/tmp/l71-${env}-data" terraform \
    -chdir="lessons/71-multi-environment-promotion/lab_71/terraform/envs/${env}" \
    validate -no-color
done
```

### Drill 3. Prove Same Module Source

```bash
for env in dev stage prod; do
  grep 'source = "../../modules/network"' \
    lessons/71-multi-environment-promotion/lab_71/terraform/envs/$env/main.tf
done
```

### Drill 4. Prove Different Inputs

```bash
for env in dev stage prod; do
  echo "--- $env"
  grep -E 'project_name|environment|vpc_cidr|tf_state_key|github_apply_environment' \
    lessons/71-multi-environment-promotion/lab_71/terraform/envs/$env/terraform.tfvars.example
done
```

### Drill 5. Run Policy Tests

```bash
lessons/71-multi-environment-promotion/policies/test-policy.sh
lessons/71-multi-environment-promotion/policies/test-opa.sh
```

### Drill 6. Successful Promotion Chain

Run the complete happy path in GitHub Actions:

1. Dev:

```text
target_env=dev
source_env=none
release_id=rel-l71-001
confirm_apply=APPLY
```

Save `lesson71-dev-plan`, `lesson71-dev-apply`, `apply-metadata.json`, and `promotion-manifest.json`.

2. Stage:

```text
target_env=stage
source_env=dev
release_id=rel-l71-001
source_workflow_run_url=<dev workflow run URL>
source_commit_sha=<dev commit SHA>
confirm_apply=APPLY
```

Save `lesson71-stage-plan`, `lesson71-stage-apply`, `apply-metadata.json`, and `promotion-manifest.json`.

3. Prod:

```text
target_env=prod
source_env=stage
release_id=rel-l71-001
source_workflow_run_url=<stage workflow run URL>
source_commit_sha=<stage commit SHA>
confirm_apply=APPLY
```

Save prod artifacts, `apply-metadata.json`, `promotion-manifest.json`, and complete `proof-pack.en.md` or `proof-pack.ru.md`.

### Drill 7. Reject Prod-First Promotion

In GitHub Actions, run the workflow with:

```text
target_env=prod
source_env=none
release_id=rel-test-prod-first
confirm_apply=APPLY
```

Expected result: the guard step fails before AWS credentials are assumed.

### Drill 8. Reject Wrong Commit Promotion

Run the workflow with:

```text
target_env=stage
source_env=dev
release_id=rel-test-wrong-sha
source_workflow_run_url=<previous dev run URL>
source_commit_sha=0000000000000000000000000000000000000000
confirm_apply=APPLY
```

Expected result: the guard step rejects the promotion because the source commit does not match the current workflow commit.

---

## Proof Pack

Use:

```text
proof-pack.en.md
proof-pack.ru.md
```

Minimum evidence:

- env matrix
- backend key proof
- plan artifact per env
- policy decision per env
- approval proof per env
- post-apply drift result per env
- `apply-metadata.json` and `promotion-manifest.json`
- promotion decision record

---

## Common Mistakes

- Reusing the same state key for multiple environments.
- Editing module code differently per env.
- Creating the same GitHub OIDC provider in multiple states.
- Approving prod before seeing plan/policy artifacts.
- Treating stage as optional.
- Running prod first.
- Letting workflow input, backend key, and GitHub Environment drift apart.

---

## Final Acceptance

You are done when:

- `envs/dev`, `envs/stage`, and `envs/prod` validate
- module tests pass
- policy tests pass
- CI template maps target env to directory/state key/GitHub Environment consistently
- proof-pack checklist explains what evidence to save
- you can explain the shared OIDC provider trap

---

## Lesson Summary

- **What you learned:** promotion is a controlled movement across isolated environment states.
- **What you practiced:** env roots, backend keys, env-specific tfvars, CI target selection, policy reuse.
- **Operational skill:** keep module source stable while changing risk controls per environment.
- **Promotion rule:** dev first, stage second, prod last..
