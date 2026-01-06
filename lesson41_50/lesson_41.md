# lesson_41

---

# Terraform CI: fmt/validate + plan in GitHub Actions

**Date:** 2025-01-04

**Topic:** Add **GitHub Actions CI** for Terraform: `fmt`, `validate`, `tflint`, `plan`.

> Outcome: every push/PR runs checks automatically, stop breaking Terraform by accident.
> 

---

## Goals

- Add CI checks that run on every push/PR:
    - `terraform fmt -check`
    - `terraform validate`
    - `tflint`
- Make the workflow work **without AWS credentials** (default).
- Enable `terraform plan` when ready (with AWS auth).
- Keep it safe: no secrets in repo, no accidental applies.

---

## Pocket Cheat

| Thing | Command / File | Why |
| --- | --- | --- |
| Format check | `terraform fmt -check -recursive` | Fail fast on style |
| Validate | `terraform validate` | Catch syntax/provider config issues |
| Lint | `tflint` | Catch Terraform/AWS mistakes |
| Plan | `terraform plan` | Show diffs before apply |
| CI workflow | `.github/workflows/terraform-ci.yml` | Automatic checks |
| Vars file | `envs/dev.tfvars` | Stable inputs for CI |
| Safe mode | no `apply` in CI | Prevent disasters |

---

## Layout

Recommended structure (matches lesson_40b):

```
labs/lesson_40/terraform/
├─ main.tf
├─ variables.tf
├─ outputs.tf
├─ envs/
│  └─ dev.tfvars
└─ modules/
   └─ network/...
.github/
└─ workflows/
   └─ terraform-ci.yml

```

---

## 1) Add CI workflow (fmt + validate + tflint)

Create: `.github/workflows/terraform-ci.yml`

```yaml
name: terraform-ci

on:
  push:
    branches: ["main"]
    paths:
      - "labs/lesson_40/terraform/**"
      - ".github/workflows/terraform-ci.yml"
  pull_request:
    paths:
      - "labs/lesson_40/terraform/**"
      - ".github/workflows/terraform-ci.yml"
  workflow_dispatch: {}

permissions:
  contents: read

concurrency:
  group: terraform-ci-${{ github.ref }}
  cancel-in-progress: true

env:
  TF_IN_AUTOMATION: "true"
  TF_INPUT: "false"
  TF_WORKING_DIR: "labs/lesson_40/terraform"

jobs:
  terraform:
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash
        working-directory: ${{ env.TF_WORKING_DIR }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.14.0"
          terraform_wrapper: false

      - name: Terraform fmt (check)
        run: terraform fmt -check -diff -recursive

      - name: Terraform init (no-backend)
        run: terraform init -backend=false -input=false -no-color

      - name: Terraform validate
        run: terraform validate -no-color

      - name: Setup TFLint
        uses: terraform-linters/setup-tflint@v6
        with:
          tflint_version: "v0.60.0"
          cache: true
          tflint_config_path: ${{ env.TF_WORKING_DIR }}/.tflint.hcl

      - name: TFLint init
        run: tflint --init
        env:
          GITHUB_TOKEN: ${{ github.token }}

      - name: TFLint
        run: tflint -f compact

```

### Add `.tflint.hcl`

Create `labs/lesson_40/terraform/.tflint.hcl`:

```hcl
plugin "aws" {
  enabled = true
  version = "0.45.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

config {
  format = "compact"
}

```

Commit these and open a PR — CI should run and pass even **without** AWS creds.

---

## 2) Add `plan` step (safe and gated, OIDC)

Reality: `terraform plan` often needs AWS access if use `data` sources or provider API calls.

To keep CI **safe**, `plan` is **gated** and runs **only when GitHub can assume an AWS role via OIDC**.

### Required permissions (enable OIDC)

Add `id-token: write` to the workflow permissions:

```yaml
permissions:
  contents: read
  id-token: write

```

### Append to the workflow job

```yaml
      - name: Configure AWS credentials (OIDC)
        if: ${{ github.event_name == 'pull_request'
            && github.event.pull_request.head.repo.full_name == github.repository }}
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>
          aws-region: eu-west-1

      - name: Terraform plan (OIDC, PR same-repo only)
        if: ${{ github.event_name == 'pull_request'
            && github.event.pull_request.head.repo.full_name == github.repository }}
        run: terraform plan -input=false -no-color -var-file=envs/dev.tfvars

```

**What this does:**

- Uses **GitHub OIDC** to assume an AWS IAM role
- No AWS keys stored in GitHub
- `plan` runs **only for PRs from the same repository** (fork PRs are skipped)
- Still **no `apply` in CI**

> CI shows what would change, but never deploys.
> 

---

## 3) AWS access model used (OIDC, no secrets)

### What are I’m using **now**

- **GitHub OIDC → AWS IAM Role**
- Short-lived credentials issued by AWS STS
- No long-lived credentials in GitHub

### What are I’m **not** using

- ❌ IAM users
- ❌ `AWS_ACCESS_KEY_ID`
- ❌ `AWS_SECRET_ACCESS_KEY`
- ❌ Static secrets in GitHub

### Why this is the recommended approach

- Nothing to rotate
- Nothing to leak
- Access is restricted by:
    - repository
    - branch / PR type
    - IAM trust policy

> Long-lived AWS keys are intentionally avoided.
> 

---

## 4) Developer workflow

- Create branch:
    
    ```bash
    git checkout -b labs/lesson_40/terraform-ci
    
    ```
    
- Commit:
    
    ```bash
    git add -A
    git commit -m "ci(terraform): add fmt/validate/tflint/plan workflow"
    git push -u origin labs/lesson_40/terraform-ci
    
    # ci(terraform): add terraform-ci workflow (fmt/validate/tflint + OIDC plan)
    ```
    
- Open PR → CI runs → if green ✅ → merge.

---

## 5) Mini runbook: when CI fails (Terraform CI)

*Applies to setup: `fmt / validate / tflint / plan (OIDC, no AWS secrets)`*

---

## 5.0 Quick triage

| CI step | Where it fails | What it usually means |
| --- | --- | --- |
| `Terraform fmt (check)` | fmt | Formatting issues |
| `Terraform init` | init | Provider/version/backend/network problem |
| `Terraform validate` | validate | Syntax, types, or module inputs |
| `TFLint init` | tflint init | Plugins/config not available |
| `TFLint` | tflint | Linting errors (Terraform/AWS rules) |
| `Configure AWS credentials (OIDC)` | OIDC | Trust policy / permissions / id-token |
| `Terraform plan` | plan | Missing vars, local files, or AWS read access |

---

## 5.1 fmt failed

### Symptom

`terraform fmt -check -diff -recursive` failed.

### Fix (locally)

```bash
cd labs/lesson_40/terraform
terraform fmt -recursive
git add -A
git commit -m "style(terraform): fmt"
git push

```

---

## 5.2 init failed

### Common causes

- Provider download failed
- Terraform / provider version mismatch
- Remote backend accidentally enabled

### Fix (locally)

```bash
cd labs/lesson_40/terraform
rm -rf .terraform .terraform.lock.hcl
terraform init -backend=false

```

### CI check

Make sure CI uses:

```bash
terraform init -backend=false -input=false -no-color

```

---

## 5.3 validate failed

### Symptom

Errors like:

- `Unexpected block`
- `Invalid value`
- `Missing required argument`

### Fix (locally)

```bash
cd labs/lesson_40/terraform
terraform init -backend=false
terraform validate

```

### Typical reasons

- Broken HCL syntax
- Wrong variable types
- Missing module inputs

---

## 5.4 tflint init failed

### Symptom

`tflint --init` fails to download plugins.

### Fix (locally)

```bash
cd labs/lesson_40/terraform
tflint --init

```

### Verify

- `.tflint.hcl` exists in `labs/lesson_40/terraform/`
- `tflint_config_path` is correct in the workflow

---

## 5.5 tflint failed

### Symptom

Warnings or errors about:

- Deprecated arguments
- Unused variables
- AWS best-practice violations

### Fix (locally)

```bash
cd labs/lesson_40/terraform
tflint --init
tflint -f compact

```

### Guidance

- Fix **errors** first, then warnings
- Disable rules only if you fully understand why

---

## 5.6 Configure AWS credentials (OIDC) failed

### Symptoms

- `Not authorized to perform sts:AssumeRoleWithWebIdentity`
- `No OIDC token available`
- `AccessDenied`

### Checks

1. Workflow permissions include:

```yaml
permissions:
  id-token: write

```

1. IAM role trust policy allows:
- `repo:VlrRbn/DevOps:ref:refs/heads/main`
- `repo:VlrRbn/DevOps:pull_request` (for PR plans)

---

## 5.7 plan failed

### 5.7a Local file paths (`file("~/.ssh/...")`)

**Symptom:**

`no file exists at /home/runner/...`

**Fix:**

Never read files from `~` in CI.

- Pass values as variables (`public_key`)
- Or keep files inside the repo and reference via `${path.module}`

---

### **5.7b** Missing AWS permissions

**Symptom:**

`AccessDenied` on `ec2:Describe*`, `iam:*`, etc.

**Fix:**

Grant read-only permissions for required services

(e.g. EC2/VPC/IAM read).

---

### **5.7c** Provider requires profile

**Symptom:**

`failed to get shared config profile`

**Fix:**

Remove `profile = ...` from `provider "aws"` — CI uses OIDC credentials.

---

### **5.7d** Missing variables

**Symptom:**

`No value for required variable`

**Fix:**

Define it in:

- `envs/dev.tfvars`
- `var`
- `TF_VAR_*`

---

## 5.8 CI is green but checks nothing

### Symptom

Workflow finishes instantly, but should have failed.

### Cause

`paths:` filter did not match changed files.

### Fix

Ensure changes touch:

- `labs/lesson_40/terraform/**`
- or `.github/workflows/terraform-ci.yml`

---

## Local commands (mirror CI exactly)

```bash
cd labs/lesson_40/terraform
terraform fmt -check -diff -recursive
terraform init -backend=false -input=false
terraform validate
tflint --init
tflint -f compact
terraform plan -input=false -no-color -var-file=envs/dev.tfvars

```

---

## Security & cost control

- ✅ CI never runs `terraform apply`
- ✅ CI has **read-only style access** (for `plan`)
- ✅ Any real changes (`apply` / `destroy`) are done **locally**
- ✅ IAM role permissions can be scoped to `Describe*` actions only

---

## Summary (clean and consistent)

- `terraform plan` runs in CI **via OIDC**
- No AWS secrets in GitHub
- IAM Role + Trust Policy control access
- CI is safe by design
- Deployment stays manual

---

## Pitfalls

- Using `plan` without creds → fails. That’s why it’s gated.
- CI working directory wrong → workflow checks nothing. (We set `working-directory` explicitly.)
- Terraform init tries remote backend → avoid for now.
- TFLint AWS plugin needs init (`tflint --init`), otherwise it looks “broken”.

---

## Core

- [ ]  Workflow added, runs on PR/push.
- [ ]  `fmt` + `validate` pass in CI.
- [ ]  `tflint` runs and passes.
- [ ]  Can intentionally break formatting to see CI fail, then fix it.
- [ ]  Add gated `plan` step +  OIDC.
- [ ]  Improve lint signal: decide which warnings matter and fix them cleanly.
- [ ]  Write 10-line “CI usage notes” in the lesson_41 doc.

---

## Artifacts

- `.github/workflows/terraform-ci.yml`
- `labs/lesson_40/when_ci_fails_eng.md`