# lesson_60

---

# Remote State & Locking (S3 Backend, Lockfile, Versioning, Safe Recovery)

**Date:** 2026-03-20

**Focus:** move Terraform state from local disk to an S3 backend with locking, versioning, encryption, and recovery discipline.

**Mindset:** no shared Terraform workflow without remote state and locking.

---

## Why This Lesson Exists

Local state is acceptable only while you are alone and disposable:

- one terminal
- no CI
- no teammate
- no long-lived environment

As soon as the same stack is touched from two places, local state becomes operational debt.

Remote state solves the real problems:

- one source of truth
- backend-managed locking
- recoverable state history via S3 versioning
- safer CI and team workflow

---

## Outcomes

- bootstrap a dedicated S3 backend for Terraform state
- migrate an existing environment from local state to remote state
- verify that state object and lockfile behavior are real, not assumed
- prove lock contention in two terminals
- understand safe lock recovery and last-resort version restore
- define the minimum IAM shape for local use and CI

---

## Quick Path (30-45 min)

1. Create backend bucket with local-state bootstrap config.
2. Add `backend "s3" {}` to one existing Terraform root.
3. Create `backend.hcl`.
4. Run `terraform init -backend-config=backend.hcl -migrate-state`.
5. Verify remote state with:
   - `terraform state pull`
   - `aws s3 ls`
   - lock contention drill in two terminals
6. Capture proof pack.

---

## Prerequisites

- AWS credentials configured locally
- Terraform working in at least one existing env directory
- lesson 56-59 mindset already familiar:
  - repeatable runbooks
  - proof-pack discipline
- understanding that Terraform state may contain sensitive values

---

## Repo Layout

Recommended layout:

```text
lab_60/terraform/
├── backend-bootstrap/
│   └── main.tf
├── envs/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars
│   └── backend.hcl.example
└── modules/
    └── network/
```

Important separation:

- `backend-bootstrap/` uses **local state only**
- your real envs later use **remote backend**

Do not try to create the backend bucket using the backend that does not exist yet.

---

## State Model You Need To Internalize

Terraform state is not only an implementation detail. It is an operational artifact.

It answers:

- what Terraform believes exists
- what resource IDs it manages
- what dependencies were already resolved
- what must be updated, replaced, or destroyed next

If state is wrong, your plan can be wrong even when your code is correct.

---

## Target Architecture

```text
Terraform (local shell / CI)
  |
  v
S3 bucket
  - terraform.tfstate object
  - object versioning
  - default encryption
  - block public access
  - TLS-only bucket policy
  |
  +-- native lockfile (.tflock)   [recommended]
  |
  +-- DynamoDB table              [legacy / optional]
```

---

## Goals / Acceptance Criteria

- [ ] state is stored in S3, not only locally
- [ ] one existing env has been migrated with `-migrate-state`
- [ ] bucket has versioning, encryption, public access block, TLS-only policy
- [ ] lock contention can be demonstrated safely
- [ ] can explain when `force-unlock` is allowed and when it is dangerous
- [ ] can fetch an older state object version for last-resort recovery
- [ ] have a minimal IAM understanding for CI/backend access

---

## A) Bootstrap The Backend

### Rule

Backend infrastructure is created first, with **local state**.

The sequence is:

1. create bucket
2. enable protection features
3. optionally create legacy DynamoDB lock table
4. only then migrate real env state into S3

### A1) Bootstrap config

Create [main.tf](lessons/60-remote-state-and-locking/lab_60/terraform/backend-bootstrap/main.tf):

```hcl
terraform {
  required_version = "~> 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for Terraform state"
}

variable "enable_dynamodb_locking" {
  type    = bool
  default = false
}

variable "dynamodb_table_name" {
  type    = string
  default = "terraform-state-locks"
}

resource "aws_s3_bucket" "tfstate" {
  bucket        = var.state_bucket_name
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name  = var.state_bucket_name
    Role  = "terraform-state"
    Owner = "DevOpsTrack"
  }
}

# Block public access to the S3 bucket to ensure state files are not publicly accessible
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning on the S3 bucket to protect against accidental deletion or overwriting of state files
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption on the S3 bucket to protect state files at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Add a bucket policy to deny any requests that do not use secure transport (HTTPS) to ensure state files are transmitted securely
data "aws_iam_policy_document" "deny_insecure_transport" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# Attach the bucket policy to the S3 bucket to enforce secure transport for all requests
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.deny_insecure_transport.json
}

# Create a DynamoDB table for state locking if enabled, with a hash key of "LockID" and on-demand billing mode. The table is protected against accidental deletion and tagged for identification.
resource "aws_dynamodb_table" "locks" {
  count        = var.enable_dynamodb_locking ? 1 : 0
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = var.dynamodb_table_name
    Role = "terraform-locks"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

output "dynamodb_table_name" {
  value = var.enable_dynamodb_locking ? aws_dynamodb_table.locks[0].name : null
}
```

### Why this config exists

- `prevent_destroy = true`
  backend loss is a serious incident
- versioning
  gives you recovery history, not just current state
- encryption
  state may contain sensitive data
- public access block
  state must never be public
- deny insecure transport
  refuse non-TLS requests

### A2) Apply bootstrap (create bucket)

Get your account ID:

```bash
aws sts get-caller-identity --query Account --output text
```

Bucket naming pattern:

```text
<prefix>-tfstate-<account-id>-<region>
"vlrrbn-tfstate-123456789012-eu-west-1"
```

Example:

```bash
cd lessons/60-remote-state-and-locking/lab_60/terraform/backend-bootstrap
terraform init
terraform apply -var="state_bucket_name=vlrrbn-tfstate-123456789012-eu-west-1"
```

Optional legacy DynamoDB mode:

```bash
terraform apply \
  -var="state_bucket_name=vlrrbn-tfstate-123456789012-eu-west-1" \
  -var="enable_dynamodb_locking=true" \
  -var="dynamodb_table_name=terraform-state-locks"
```

### A3) Verify backend bucket

```bash
aws s3api get-bucket-versioning --bucket vlrrbn-tfstate-123456789012-eu-west-1
aws s3api get-public-access-block --bucket vlrrbn-tfstate-123456789012-eu-west-1
aws s3api get-bucket-encryption --bucket vlrrbn-tfstate-123456789012-eu-west-1
```

If AWS CLI appears to hang, retry with explicit region, no pager, and short timeouts:

```bash
aws s3api get-bucket-encryption \
  --bucket vlrrbn-tfstate-123456789012-eu-west-1 \
  --region eu-west-1 \
  --no-cli-pager \
  --cli-connect-timeout 5 \
  --cli-read-timeout 10
```

---

## B) Decide Your Locking Mode

### Recommended

Use S3 native lockfile:

```hcl
use_lockfile = true
```

This is configured in the working env backend file, for example [backend.hcl](lessons/60-remote-state-and-locking/lab_60/terraform/envs/backend.hcl), not in `backend-bootstrap/`.

Why:

- one less AWS component
- simpler permissions
- easier to teach and operate

### Legacy / Optional

Use DynamoDB only if you explicitly need to support older conventions:

```hcl
dynamodb_table = "terraform-state-locks"
```

For this track, native S3 locking is the default mental model.

---

## C) Wire Remote Backend Into An Existing Env

### C1) Add backend block

Inside the Terraform root you want to migrate, add:

```hcl
terraform {
  backend "s3" {}
}
```

Reason:

- backend values cannot come from normal Terraform variables
- backend config is supplied during `terraform init`

### C2) Create backend.hcl

Example [backend.hcl](lessons/60-remote-state-and-locking/lab_60/terraform/envs/backend.hcl):

```hcl
bucket       = "vlrrbn-tfstate-123456789012-eu-west-1"
key          = "lab60/dev/full/terraform.tfstate"
region       = "eu-west-1"
encrypt      = true
use_lockfile = true
```

Key naming rule:

```text
<project>/<environment>/<stack>/terraform.tfstate
```

Examples:

- `lab56/prod/web/terraform.tfstate`
- `lab60/dev/full/terraform.tfstate`
- `shared/tools/backend-bootstrap/terraform.tfstate`

Never reuse the same `key` for different envs.

### C3) Migrate state

From the target envs directory:

```bash
terraform init -backend-config=backend.hcl -migrate-state
```

Terraform asks whether to copy local state into the backend.  
For the migration you want: **yes**.

Use `-migrate-state` for the first move from local state to remote backend.  
Use `-reconfigure` later only when backend settings changed and you are not migrating state.

---

## D) Verify Migration Properly

### D1) Pull state through backend

```bash
terraform state pull | head -n 20
```

Meaning:

- Terraform now reads through the backend
- you are no longer proving only local files exist

### D2) Check object exists in S3

```bash
aws s3 ls s3://vlrrbn-tfstate-123456789012-eu-west-1/lab60/dev/full/terraform.tfstate
```

### D3) Optional: show backend metadata

```bash
terraform init -reconfigure -backend-config=backend.hcl
```

If backend is already configured correctly, this should reinitialize cleanly.

### D4) Local file sanity

If there used to be a local `terraform.tfstate` or `terraform.tfstate.backup` in `envs/`, do not use them anymore as source of truth after successful backend migration.

Your source of truth is now:

- remote backend object
- `terraform state pull`

---

## E) Locking Drills (Prove It Works)

### Drill 1: Lock contention in two terminals

Terminal A:

```bash
terraform apply
```

When Terraform waits for approval, stop there. Do not confirm yet.

Important: this drill requires a non-empty plan.  
If Terraform says `No changes`, first introduce one harmless temporary diff so terminal A really holds the lock at approval time.

Terminal B:

```bash
terraform plan -lock-timeout=30s
```

Expected:

- terminal B fails or waits with lock-related message
- only one operation owns state at a time

### Drill 2: Observe lockfile behavior

While terminal A still holds the lock:

```bash
aws s3 ls s3://vlrrbn-tfstate-123456789012-eu-west-1/lab60/dev/full/
```

With native locking you should see the state object and lockfile behavior around:

```text
terraform.tfstate
terraform.tfstate.tflock
```

### Drill 3: Safe lock recovery

Only if a lock is stale and you are certain no Terraform process is still active:

```bash
terraform force-unlock <LOCK_ID>
```

Safe use:

- your process crashed
- CI job is dead
- no second operator is actively running Terraform

Unsafe use:

- you are impatient
- another apply may still be running
- you did not verify ownership of the lock

If you misuse `force-unlock`, you can create concurrent state corruption.

---

## F) Versioning Drill (Recovery Mindset)

Versioning is not for casual rollback.  
It is for last-resort recovery and investigation.

### F1) List versions

```bash
aws s3api list-object-versions \
  --bucket vlrrbn-tfstate-123456789012-eu-west-1 \
  --prefix lab60/dev/full/terraform.tfstate
```

### F2) Download older version

```bash
aws s3api get-object \
  --bucket vlrrbn-tfstate-123456789012-eu-west-1 \
  --key lab60/dev/full/terraform.tfstate \
  --version-id <VERSION_ID> \
  /tmp/terraform.tfstate.old
```

### F3) Inspect, do not blindly replace

```bash
jq '.serial, .lineage, .resources | length' /tmp/terraform.tfstate.old
```

Why this matters:

- old state may not match real infrastructure anymore
- restoration is an incident-level action

---

## G) CI + IAM Minimum Shape (Awareness Section)

For S3 backend with native lockfile, CI/backend access normally needs:

- `s3:ListBucket`
- `s3:GetObject`
- `s3:PutObject`
- `s3:DeleteObject`

Why `DeleteObject` matters:

- native lockfile must be removed after successful operation

If you use DynamoDB locking, add:

- `dynamodb:DescribeTable`
- `dynamodb:GetItem`
- `dynamodb:PutItem`
- `dynamodb:DeleteItem`

Rules:

- no static keys in backend config
- use environment credentials, AWS profile, or OIDC-backed CI role
- remember backend config values may end up under `.terraform/`

---

## H) Normal Operator Runbook

When remote backend is already in place, normal Terraform flow becomes:

1. `terraform init` with backend configured
2. `terraform plan`
3. `terraform apply`
4. if lock error happens:
   - verify active process first
   - only then consider timeout or `force-unlock`
5. if state incident happens:
   - inspect current remote state
   - inspect older S3 versions
   - recover carefully, not blindly

The point of remote state is not only storage.  
It is safe operation under concurrency.

---

## Proof Pack (Must-have Evidence)

Detailed collection guide:

- [proof-pack.en.md](lessons/60-remote-state-and-locking/proof-pack.en.md)

- bootstrap apply output
- versioning/encryption/public-access-block verification output
- successful `terraform init -migrate-state`
- `terraform state pull` output header
- `aws s3 ls` showing remote state object
- lock contention output from second terminal
- `list-object-versions` output

---

## Common Pitfalls

- creating backend bucket inside the backend that does not exist yet
- using one shared `key` for multiple envs
- trusting old local `terraform.tfstate` after migration
- using `force-unlock` without verifying active operations
- treating old S3 state version as instant safe rollback

---

## Final Acceptance

- [ ] backend bucket exists with versioning, encryption, public access block
- [ ] one env migrated to S3 backend successfully
- [ ] `terraform state pull` works against remote backend
- [ ] S3 object exists at expected `bucket + key`
- [ ] lock contention reproduced in two terminals
- [ ] you can explain safe vs unsafe `force-unlock`
- [ ] you can download and inspect an older state version

---

## Security Checklist

- backend bucket is private
- TLS-only bucket policy is enabled
- state encryption is enabled
- backend IAM is least-privilege
- no backend secrets are hardcoded
- state is treated as sensitive operational data

---

## Lesson Summary

Lesson 60 is where Terraform state becomes operationally correct:

- remote instead of local
- locked instead of racy
- versioned instead of fragile
- recoverable instead of guess-based
