# lesson_43

---

# GitHub OIDC → AWS IAM Role for Terraform CI from the start

**Date:** 2025-01-09

**Topic: Dont use** `AWS_ACCESS_KEY_ID/SECRET` in GitHub Secrets, **OIDC would be safer** (short-lived creds). Configure:

- AWS **OIDC provider**
- IAM **Role** with strict trust policy (repo + branch)
- Least-privilege permissions for **Terraform plan**
- GitHub Actions workflow using `aws-actions/configure-aws-credentials@v4`

References: GitHub’s AWS OIDC guide and OIDC claim reference + AWS action docs. ([GitHub Docs](https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services))

---

## Goals

- CI authenticates to AWS using **OIDC**, no static secrets.
- Role assumption is restricted to **repo** and **main branch**.
- Workflow can run `terraform plan` safely (no apply).
- Debug auth quickly via `aws sts get-caller-identity`.

---

## Pocket Cheat

| What | Where | Why |
| --- | --- | --- |
| Enable OIDC token | `permissions: id-token: write` | Without it, AWS role cannot be assumed ([GitHub](https://github.com/aws-actions/configure-aws-credentials)) |
| Assume role via OIDC | `aws-actions/configure-aws-credentials@v4` | Standard GitHub→AWS pattern |
| Lock role to repo/branch | IAM Trust Policy `sub` + `aud` conditions | Prevent other repos/branches from assuming role |
| Check identity | `aws sts get-caller-identity` | Fast sanity test |

---

## 1) AWS: create the GitHub OIDC Identity Provider

In AWS IAM → **Identity providers**:

- Provider type: **OpenID Connect**
- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

This is the standard GitHub OIDC issuer. ([GitHub Docs](https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services))

---

## 2) AWS: create an IAM role for CI

Role name suggestion: `GitHub`

Trusted entity: **Web identity** → select your GitHub OIDC provider.

### Trust policy (strict, recommended)

Replace:

- `<ACCOUNT_ID>`
- `<OWNER>` = `VlrRbn`
- `<REPO>` = `DevOps`

Use this trust relationship:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::179151669003:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": [
                        "repo:<OWNER>/<REPO>:ref:refs/heads/main",
                        "repo:<OWNER>/<REPO>:pull_request"
                    ]
                }
            }
        }
    ]
}

```

But if you know exactly which values you expect, it’s safer to restrict them explicitly.

```json
"StringEquals": {
  "token.actions.githubusercontent.com:sub": "repo:<OWNER>/<REPO>:ref:refs/heads/main"
}

```

And for PRs, use a separate role or a separate policy statement. That reduces the attack surface.

Why this matters:

- `aud=sts.amazonaws.com` is the expected audience in GitHub→AWS setups.
- `sub` ties the role to a **single repo + branch**. GitHub documents how `sub` is formed and customizable. ([GitHub Docs](https://docs.github.com/actions/reference/openid-connect-reference))
- Branch-only trust will block PR runs on non-main branches

And we can add “[Restrict by Workflow](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-with-reusable-workflows)”

```json
"token.actions.githubusercontent.com:job_workflow_ref":
  "OWNER/REPO/.github/workflows/terraform-ci.yml@refs/heads/main"

```

Plus: even if someone creates a new workflow, the role won’t be assumable.

Downside: the workflow path becomes part of security contract.

---

## 3) AWS permissions policy for Terraform plan

Two approaches:

### Approach 1 (fastest): attach AWS managed `ReadOnlyAccess`

Pros: works quickly. Cons: too broad.

### Approach 2 (better): minimal “plan-read” policy

Start small and expand when plan complains. Example baseline:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["sts:GetCallerIdentity"], "Resource": "*" },
    { "Effect": "Allow", "Action": ["ec2:Describe*"], "Resource": "*" },
    { "Effect": "Allow", "Action": ["iam:Get*", "iam:List*"], "Resource": "*" }
  ]
}

```

Terraform plan often fails not because of bugs, but because of missing `Describe*` permissions — that’s normal.

Terraform planning a VPC stack typically needs `ec2:Describe*` heavily; IAM reads only if you reference IAM resources/data. (If don’t, you can omit IAM.)

Keep it read-only for CI.

---

## 4) GitHub Actions: update your Terraform CI workflow

In `.github/workflows/terraform-ci.yml`:

### Required permissions

```yaml
permissions:
  contents: read
  id-token: write

```

### Add OIDC auth step (before plan)

```yaml
- name: Configure AWS credentials (OIDC)
  if: ${{ github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository }}
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::179151669003:role/GitHub
    aws-region: eu-west-1

- name: Terraform plan (OIDC, PR same-repo only)
  if: ${{ github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository }}
  run: terraform plan -input=false -no-color -var-file=envs/dev.tfvars

```

This is the official action for assuming roles (including OIDC).

### Add identity check (high-signal debug)

```yaml
- name: AWS identity
  run: aws sts get-caller-identity

```

### Add plan step (no apply)

```yaml
- name: Terraform init
  run: terraform init -input=false

- name: Terraform plan (safe)
  run: terraform plan -input=false -no-color -var-file=envs/dev.tfvars

```

---

## 5) Common Pitfalls

- Missing `id-token: write` → OIDC token cannot be requested. ([GitHub Docs](https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services))
- `sub` mismatch (repo name / branch / ref format) → trust policy denies assume. GitHub’s OIDC reference explains `sub`.
- Running workflow from a fork PR (security model differs) → may fail by design.
- Terraform uses local paths like `~/.ssh/...` in CI → runner won’t have that file. Prefer repo path or variables.

---

## Core

- [ ]  OIDC provider created in AWS.
- [ ]  IAM role created with trust policy restricted to my repo.
- [ ]  Workflow assumes role and prints `get-caller-identity`.
- [ ]  `terraform plan` runs in CI (read-only).
- [ ]  Tighten trust policy:
    - only allow `main` or only allow specific workflow
- [ ]  Replace broad permissions with minimal policy based on what plan actually needs.
- [ ]  Add a second role later for “apply” (but keep it disabled until explicitly decide).

---

## Artifacts

- `runbook/debugging_GA_AWS_OIDC_auth.md`
