# lesson_43 GitHub OIDC → AWS IAM Role for Terraform CI

# Runbook: Debugging GitHub Actions → AWS OIDC Authentication
Mini runbook from lesson_40: when_ci_fails_eng.md


This runbook helps diagnose issues when a GitHub Actions workflow **fails to assume an AWS IAM role via OIDC**.

---

## 1. Symptom

Typical errors include:

* `Error: Not authorized to perform sts:AssumeRoleWithWebIdentity`
* `AccessDenied: Could not assume role`
* AWS credentials are missing
* Terraform fails early with AWS auth errors

---

## 2. Quick Sanity Check (Start Here)

Add this step **after** `configure-aws-credentials`:

```yaml
- name: AWS identity check
  run: aws sts get-caller-identity
```

### Expected result

* Command succeeds
* Correct AWS Account ID
* Correct Role ARN

If this fails → the problem is **OIDC / IAM**, not Terraform.

---

## 3. Verify GitHub Workflow Configuration

### 3.1 Required permissions

Ensure the workflow has:

```yaml
permissions:
  contents: read
  id-token: write
```

Missing `id-token: write` = GitHub **cannot issue** an OIDC token.

---

### 3.2 Correct action usage

Verify you are using the official action:

```yaml
uses: aws-actions/configure-aws-credentials@v4
```

Check:

* `role-to-assume` ARN is correct
* `aws-region` is set
* Step runs **before** any AWS/Terraform command

---

### 3.3 Forked PR protection

If running on `pull_request`, confirm this condition exists:

```yaml
if: github.event.pull_request.head.repo.full_name == github.repository
```

Fork PRs **cannot** assume AWS roles by design.

---

## 4. Verify IAM Trust Policy

### 4.1 Audience (`aud`) condition

IAM trust policy **must include**:

```json
"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
```

Any other value → role assumption denied.

---

### 4.2 Subject (`sub`) condition

Confirm the `sub` **exactly matches** the workflow context.

Examples:

* Main branch:

  ```
  repo:OWNER/REPO:ref:refs/heads/main
  ```

* Pull request:

  ```
  repo:OWNER/REPO:pull_request
  ```

Common mistakes:

* Wrong repo name (case-sensitive)
* Wrong branch name
* Missing `refs/heads/`
* Using `main` vs `master`

---

### 4.3 StringEquals vs StringLike

* Use `StringEquals` when matching a **single known value**
* Use `StringLike` only when pattern matching is required

Overly broad `StringLike` increases risk; overly strict matching may block CI.

---

## 5. Check OIDC Provider in AWS

In IAM → Identity providers:

* Provider URL:

  ```
  https://token.actions.githubusercontent.com
  ```
* Audience:

  ```
  sts.amazonaws.com
  ```

Wrong URL or missing audience → token rejected.

---

## 6. Terraform-Specific Notes

If OIDC works but `terraform plan` fails:

* This is **not** an auth issue — it’s a permissions issue.
* Terraform often needs more than expected read permissions.

Common missing permissions:

* `ec2:DescribeAvailabilityZones`
* `ec2:DescribeAccountAttributes`
* `ec2:DescribeVpcEndpointServices`
* `kms:DescribeKey`
* `s3:GetBucketLocation`

Expand permissions **incrementally** based on error messages.

---

## 7. Final Checklist

Before escalating:

* [ ] `id-token: write` is present
* [ ] Workflow is not running from a fork
* [ ] `aws sts get-caller-identity` succeeds
* [ ] IAM `aud` = `sts.amazonaws.com`
* [ ] IAM `sub` matches repo + branch **exactly**
* [ ] Correct role ARN is used
* [ ] OIDC provider exists and is enabled

---

## 8. Rule of Thumb

> If `get-caller-identity` fails — fix IAM/OIDC.
> If `terraform plan` fails — fix permissions.
