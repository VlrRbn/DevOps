# Mini runbook: when CI fails (Terraform CI)

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

## 1) fmt failed

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

## 2 init failed

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

## 3 validate failed

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

## 4 tflint init failed

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

## 5 tflint failed

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

## 6 Configure AWS credentials (OIDC) failed

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

2. IAM role trust policy allows:
- `repo:VlrRbn/DevOps:ref:refs/heads/main`
- `repo:VlrRbn/DevOps:pull_request` (for PR plans)

---

## 7 plan failed

### 7a Local file paths (`file("~/.ssh/...")`)

**Symptom:**

`no file exists at /home/runner/...`

**Fix:**

Never read files from `~` in CI.

- Pass values as variables (`public_key`)
- Or keep files inside the repo and reference via `${path.module}`

---

### **7b** Missing AWS permissions

**Symptom:**

`AccessDenied` on `ec2:Describe*`, `iam:*`, etc.

**Fix:**

Grant read-only permissions for required services

(e.g. EC2/VPC/IAM read).

---

### **7c** Provider requires profile

**Symptom:**

`failed to get shared config profile`

**Fix:**

Remove `profile = ...` from `provider "aws"` — CI uses OIDC credentials.

---

### **7d** Missing variables

**Symptom:**

`No value for required variable`

**Fix:**

Define it in:

- `envs/dev.tfvars`
- `var`
- `TF_VAR_*`

---

## 8 CI is green but checks nothing

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