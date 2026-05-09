# lesson_63

---

# Terraform CI Plan Pipeline (OIDC, Remote State, PR-Safe Delivery)

**Date:** 2026-05-09

**Focus:** build a read-only Terraform PR plan pipeline using GitHub Actions, OIDC, remote state, concurrency control, and plan artifacts.

**Mindset:** quality gates tell you whether the code looks acceptable; a plan pipeline tells you what Terraform would do before merge.

---

## Why This Lesson Exists

Quality gates answer:

- is the HCL formatted?
- is the configuration valid?
- does it violate your lint or policy baseline?

They do **not** answer on important delivery question:

> What will this pull request actually do to infrastructure?

That is the role of a CI **plan pipeline**.

Terraform PR workflow should:

- run automatically on pull requests
- authenticate to AWS without long-lived static keys
- use the existing remote backend safely
- produce a readable `terraform plan`
- upload plan artifacts for review
- never run `apply`

---

## Outcomes

- build a GitHub Actions workflow for Terraform plan on PRs
- authenticate to AWS using GitHub OIDC assume-role
- use remote S3 backend safely from CI
- prevent parallel CI runs from fighting each other
- upload a human-readable plan artifact
- capture success and failure evidence for review
- explain why CI plan is a review tool, not an apply tool

---

## Quick Path

1. Define the target PR workflow shape.
2. Prepare an AWS IAM role for GitHub OIDC.
3. Scope the workflow to the lesson Terraform path only.
4. Run `fmt`, `validate`, `tflint`, `checkov`, then `terraform plan`.
6. Add concurrency so only the latest PR run lives.
7. Prove both success and failure paths.

---

## Prerequisites

- lesson 60 completed: remote state and locking
- lesson 61 completed: safe refactors and state hygiene
- lesson 62 completed: Terraform quality gates baseline

---

## Repo Layout

```text
lessons/63-terraform-ci-plan-pipeline/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── terraform-plan-pr.yml
└── lab_63/
    ├── packer/
    └── terraform/
        ├── .tflint.hcl
        ├── backend-bootstrap/
        ├── envs/
        └── modules/network/
```

---

## Target Flow

```text
Pull Request
  |
  v
GitHub Actions
  |
  +--> terraform fmt -check
  +--> terraform validate
  +--> tflint
  +--> checkov
  +--> terraform plan
           |
           v
      artifact upload
           |
           v
   reviewer reads plan before merge
```

Critical rule:

- CI may **plan**
- CI may **never apply**

---

## A) Delivery Model You Need To Internalize

Terraform delivery chain is now:

1. local edit
2. local quick checks
3. push branch
4. open PR
5. CI runs quality gates
6. CI runs a read-only Terraform plan
7. reviewer checks both code and plan output
8. merge happens only after understanding the infrastructure impact

---

## B) Authentication Model: OIDC, Not Static AWS Keys

Do not store long-lived AWS access keys in GitHub secrets for Terraform CI if you can avoid it.

Use GitHub Actions OIDC so the job receives short-lived credentials by assuming an IAM role.

Benefits:

- no long-lived AWS keys in GitHub
- IAM trust can be narrowed to your repo
- cleaner AWS audit trail
- less secret sprawl across environments

Required GitHub job permissions:

```yaml
permissions:
  id-token: write
  contents: read
```

If you later want PR comments, add:

```yaml
  pull-requests: write
```

`id-token: write` is what allows GitHub to mint the OIDC token.

---

## C) AWS Side: IAM Role for GitHub Actions

Create or reuse an IAM role that GitHub Actions can assume.

### Trust Policy Shape

Allow:

- `token.actions.githubusercontent.com` as federated principal
- `aud = sts.amazonaws.com`
- `sub` restricted to repo

Example trust policy:

```json
{
  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch}"
          }
        }
      }
    ]
  })
}
```

### CI Role Permission Shape

For a plan-only pipeline, the role usually needs:

- backend access for the S3 state object and lockfile
- read access to resources Terraform refreshes during plan
- no broad mutate permissions unless your provider behavior truly requires them

Practical note:

`terraform plan` is not fully “read-only”. It still interacts with the remote backend and refreshes provider state.
But scope the role tightly anyway.

---

## D) Workflow Design Rules

### 1. Trigger only for relevant paths

Do not run Terraform CI on every README change in the whole repo.

Good path filter:

```yaml
on:
  pull_request:
    paths:
      - 'lessons/63-terraform-ci-plan-pipeline/lab_63/terraform/**'
      - '.github/workflows/terraform-plan-pr.yml'
```

Adjust to your real repo layout.

### 2. Concurrency is mandatory

If you push three times to the same PR, only the latest run should survive.

```yaml
concurrency:
  group: terraform-plan-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
```

Without this, CI turns into noise plus backend contention.

### 3. Backend config must be explicit

CI must know:

- backend bucket
- state key
- region
- lockfile mode

Never assume a local machine state or a manually created hidden file.

### 4. CI must not migrate state

Use:

```bash
terraform init -reconfigure -backend-config=backend.hcl
```

Do **not** use `-migrate-state` in CI.

State migration is an operator action, not a pipeline action.

---

## E) Example Workflow (`ci/terraform-plan-pr.yml`)

This lesson keeps the workflow next to the lesson first. Copy it into `.github/workflows/` only when you are ready.

Recommended repo variables / secrets:

- `vars.AWS_REGION`
- `vars.TF_PLAN_ROLE_ARN`
- `vars.TF_STATE_BUCKET`

Example:

```yaml
name: terraform-plan-pr

on:
  pull_request:
    paths:
      - 'lessons/63-terraform-ci-plan-pipeline/lab_63/terraform/**'
      - '.github/workflows/terraform-plan-pr.yml'
  workflow_dispatch: {}

permissions:
  id-token: write
  contents: read

concurrency:
  group: terraform-plan-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

env:
  TF_ROOT: lessons/63-terraform-ci-plan-pipeline/lab_63/terraform
  TF_IN_AUTOMATION: true
  TF_INPUT: false
  AWS_REGION: ${{ vars.AWS_REGION || 'eu-west-1' }}

jobs:
  terraform-plan:
    if: ${{ github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository }}
    runs-on: ubuntu-latest

    defaults:
      run:
        shell: bash
        working-directory: ${{ env.TF_ROOT }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: '1.14.0'
          terraform_wrapper: false

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: ${{ env.AWS_REGION }}
          role-to-assume: ${{ vars.TF_PLAN_ROLE_ARN }}
          role-session-name: gha-terraform-plan

      - name: Terraform fmt
        run: terraform fmt -check -recursive

      - name: Terraform init (no backend)
        run: terraform -chdir=envs init -backend=false -input=false -no-color

      - name: Terraform validate
        run: terraform -chdir=envs validate -no-color

      - name: Setup TFLint
        uses: terraform-linters/setup-tflint@v6
        with:
          tflint_version: 'v0.60.0'
          cache: true

      - name: TFLint init
        run: tflint --chdir=envs --config=../.tflint.hcl --init
        env:
          GITHUB_TOKEN: ${{ github.token }}

      - name: TFLint
        run: tflint --chdir=envs --config=../.tflint.hcl -f compact

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install Checkov
        run: pip install checkov==3.2.469

      - name: Checkov
        run: checkov -d . --framework terraform --config-file ../../checkov.yaml

      - name: Write backend.hcl
        working-directory: ${{ env.TF_ROOT }}/envs
        run: |
          cat > backend.hcl <<EOF
          bucket       = "${{ vars.TF_STATE_BUCKET }}"
          key          = "lab63/dev/full/terraform.tfstate"
          region       = "${{ env.AWS_REGION }}"
          encrypt      = true
          use_lockfile = true
          EOF

      - name: Terraform init (remote backend)
        run: terraform -chdir=envs init -reconfigure -backend-config=backend.hcl -input=false -no-color

      - name: Terraform plan
        run: terraform -chdir=envs plan -input=false -no-color -out=tfplan | tee envs/plan.txt

      - name: Terraform show
        run: terraform -chdir=envs show -no-color tfplan > envs/tfplan.txt

      - name: Upload plan artifact
        uses: actions/upload-artifact@v4
        with:
          name: terraform-plan
          path: |
            ${{ env.TF_ROOT }}/envs/tfplan
            ${{ env.TF_ROOT }}/envs/tfplan.txt
            ${{ env.TF_ROOT }}/envs/plan.txt

      - name: Job summary
        run: |
          {
            echo "## Terraform PR Plan"
            echo
            echo "- fmt: passed"
            echo "- validate: passed"
            echo "- tflint: passed"
            echo "- checkov: passed"
            echo "- plan artifact: uploaded"
          } >> "$GITHUB_STEP_SUMMARY"
```

---

## F) Plan Review Discipline

For every non-trivial PR, answer these four questions:

- what will be added?
- what will change?
- what will be destroyed?
- is that expected?

---

## G) Proof Pack (Must-Have Evidence)

Collect at least:

- successful PR plan run
- failed validate run
- failed `checkov` or `tflint` run
- uploaded plan artifact evidence
- concurrency cancellation evidence
- short decision note:
  - what changed
  - what CI showed
  - why that is useful before merge

See `proof-pack.en.md` for a concrete collection pattern.

---

## Drills (Mandatory)

### Drill 1: Healthy PR plan

Make a safe, visible change:

- tag change
- alarm description change
- comment-safe tweak that still produces a plan

Expected:

- workflow passes
- plan artifact exists
- summary is readable

### Drill 2: Broken HCL

Introduce a syntax or invalid reference mistake.

Expected:

- workflow fails at `validate`
- `plan` is never reached

### Drill 3: Policy break

Reintroduce one lesson 62 footgun:

- remove IMDSv2 requirement
- open public ingress
- weaken backend protection inside the lesson scope

Expected:

- workflow fails at `checkov` and/or `tflint`

### Drill 4: Concurrency proof

Push two commits quickly to the same PR.

Expected:

- the first run is canceled
- the latest run survives

---

## Common Pitfalls

- using static AWS keys instead of OIDC
- letting CI run `apply`
- missing concurrency guard
- backend config hardcoded carelessly in repo
- path filters too broad or too narrow
- assuming `validate` is enough and skipping real `plan`
- treating plan artifacts as noise instead of review data

---

## Final Acceptance

Lesson 63 is complete if:

- [ ] GitHub Actions runs Terraform plan on PRs
- [ ] AWS auth works through OIDC assume-role
- [ ] remote backend init works in CI
- [ ] plan artifact is uploaded
- [ ] broken code fails before `plan`
- [ ] concurrency cancellation is visible
- [ ] you can explain the plan before merge

---

## Lesson Summary

- **What you learned:** how to build a safe Terraform PR plan pipeline.
- **What you practiced:** OIDC auth, backend-aware CI, concurrency control, artifact upload, fail-fast delivery.
- **Operational focus:** plan before merge, apply later and separately.
- **Why it matters:** quality gates catch bad code, but plan shows real infrastructure impact.
