# Lesson 65. Secrets, Sensitive Data & Safe Inputs

**Date:** 2026-05-13

**Focus:** prevent secrets from leaking through Terraform code, state, plan artifacts, CI logs, variables, and outputs.

**Mindset:** secrets management is not “where do I put a password”; it is “where can this value accidentally appear”.

---

## Why This Lesson Exists

After lesson 64, workflow can detect drift between Terraform code and AWS reality.

Now the next risk is different:

- secrets in `terraform.tfvars`
- sensitive values in state
- plan artifacts uploaded to CI
- output values printed to logs
- backend config leaked into `.terraform/`
- passwords passed through user-data
- accidental commits

Terraform can redact sensitive values in CLI output, but marking a value as `sensitive` does **not automatically mean it is absent from state**. Terraform documentation explicitly notes that sensitive variables are redacted from CLI output, while ephemeral values are the mechanism for omitting supported values from state and plan files. ([HashiCorp Developer](https://developer.hashicorp.com/terraform/language/block/variable))

This lesson is about building a safe mental model. Terraform should manage access and references, not drag plaintext secrets through the pipeline.

---

## Outcomes

- understand what Terraform `sensitive` does and does not protect
- identify where secrets can leak:
  - code
  - tfvars
  - state
  - plan artifacts
  - CI logs
  - outputs
  - user-data
- move secret-like values into safer stores:
  - SSM Parameter Store
  - AWS Secrets Manager
- design Terraform variables and outputs with safe defaults
- add local and CI checks to catch accidental secret commits
- run drills that prove secrets do not appear where they should not

---

## Quick Path

1. Classify all values in your lab:
   - public config
   - internal config
   - sensitive
   - secret
2. Add `sensitive = true` where appropriate.
3. Remove secret-like values from committed `.tfvars`.
4. Store one value in SSM Parameter Store.
5. Store one value in Secrets Manager.
6. Prove:
   - value is not committed
   - value is not printed in outputs
   - CI artifacts do not expose it
   - state is treated as sensitive
7. Add secret scanning to the quality gate.

---

## Prerequisites

- lesson 60: remote state + locking
- lesson 63: PR plan pipeline
- lesson 64: drift detection workflow
- AWS CLI configured
- GitHub Actions workflow available
- basic IAM understanding

---

## Repo Layout

```
lessons/65-secrets-sensitive-data-and-safe-inputs/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── secrets-scan.yml
└── lab_65/
    └── terraform/
        ├── envs/
        │   ├── main.tf
        │   ├── variables.tf
        │   ├── outputs.tf
        │   ├── terraform.tfvars.example
        │   └── backend.hcl.example
        └── modules/network/
```

---

## A) Secret Exposure Model

A value can leak through more places than expect.

| Location | Risk |
| --- | --- |
| `.tf` files | committed forever |
| `.tfvars` | often accidentally committed |
| Terraform state | may contain sensitive resource arguments |
| plan files | can contain operational details |
| CI artifacts | downloadable by people with repo access |
| outputs | easy to print into logs |
| user-data | visible from instance metadata / cloud-init history |
| shell history | local leak |
| GitHub Actions logs | accidental echo |

The important rule:

> If a value enters Terraform, assume it may reach state unless proven otherwise.

Terraform’s S3 backend stores the state as an object in S3 at the configured bucket/key path, so your remote state bucket must be treated as sensitive infrastructure, not as “just storage”. ([HashiCorp Developer](https://developer.hashicorp.com/terraform/language/backend/s3))

### Safe Secret Flow

The goal of this lesson is to keep plaintext secret values out of Terraform:

```text
Developer / operator
  -> creates the secret value in AWS SSM or Secrets Manager
  -> Terraform grants an IAM role permission to read a specific secret name/path
  -> EC2 instance or application reads the secret at runtime
  -> proof pack stores only metadata and REDACTED results
```

Unsafe flow:

```text
secret value
  -> terraform.tfvars
  -> Terraform resource argument
  -> state / plan / CI artifact
```

---

## B) Classification: Config vs Sensitive vs Secret

Use this decision table.

| Type | Example | Safe in Git? | Safe in state? | Notes |
| --- | --- | --- | --- | --- |
| Public config | region, project name | yes | yes | normal input |
| Internal config | VPC CIDR, subnet CIDRs | usually | yes | not secret, but operational |
| Sensitive | account IDs, ARNs, internal DNS | sometimes | usually | avoid public sharing |
| Secret | passwords, tokens, private keys | no | avoid | use secret stores |

### Practice task

Create a table in your lesson with at least 10 values from your lab:

```markdown
| Value | Classification | Current location | Target location |
|---|---|---|---|
| AWS region | public config | tfvars | tfvars |
| ALB DNS | internal config | output | output |
| Telegram token | secret | not used here | Secrets Manager |
| DB password | secret | not used here | Secrets Manager |
```

Criteria: be able to explain why each value fell into this category.

### Lab 65 Classification Example

Important: **not secret** does not mean **public**.

| Value | Classification | Why |
| --- | --- | --- |
| `aws_region` | public config | the region itself does not expose a secret |
| `project_name` | public config | the lesson project name is not secret |
| `vpc_cidr` | internal config | part of the network layout |
| `public_subnet_cidrs` | internal config | also network layout, despite the word `public` |
| `web_ami_id` | internal config / sensitive | may reveal account/region-specific build details |
| `ssm_proxy_private_ip` | internal config / sensitive | internal infrastructure address |
| `alb_dns_name` | internal config / sensitive | internal endpoint |
| `tf_plan_role_arn` | sensitive | exposes the IAM role ARN used by CI |
| `demo_api_token_parameter_name` | internal config | this is the secret location, not the value |
| `demo_app_secret_name` | internal config | this is the secret location, not the value |

---

## C) Terraform `sensitive`

### Example variable

```hcl
variable "admin_password" {
  type        = string
  description = "Example secret value for lesson 65. Do not commit real secrets."
  sensitive   = true
}
```

### Example output

```hcl
output "admin_password_demo" {
  value     = var.admin_password
  sensitive = true
}
```

This prevents CLI output from showing the value directly, but it does not mean you should pass real secrets through Terraform casually. Terraform’s docs describe `sensitive` as redaction in CLI output, while ephemeral values are the newer mechanism for supported cases where values should be omitted from state and plan files. ([HashiCorp Developer](https://developer.hashicorp.com/terraform/language/block/variable))

### Acceptance

- [ ]  You can explain what `sensitive = true` protects
- [ ]  You can explain what it does **not** protect
- [ ]  You do not treat it as a secret storage solution

### Bad and Good Pattern

Bad: the secret value flows through Terraform input.

```hcl
variable "api_token_value" {
  type      = string
  sensitive = true
}

resource "aws_ssm_parameter" "api_token" {
  name  = "/devops/lab65/demo/api-token"
  type  = "SecureString"
  value = var.api_token_value
}
```

Why it is bad: `sensitive = true` redacts output, but the value may still land in state or plan.

Good: Terraform knows only the secret name and grants runtime access.

```hcl
variable "demo_api_token_parameter_name" {
  type    = string
  default = "/devops/lab65/demo/api-token"
}

data "aws_iam_policy_document" "runtime_secret_read" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:REGION:ACCOUNT_ID:parameter/devops/lab65/demo/api-token"]
  }
}
```

Bad: an output exposes the secret value.

```hcl
output "app_secret_string" {
  value = aws_secretsmanager_secret_version.app.secret_string
}
```

Good: an output exposes only metadata.

```hcl
output "demo_app_secret_name" {
  value       = var.demo_app_secret_name
  description = "Secret name only. This is metadata, not the secret value."
}
```

---

## D) Safe Input Files

### Rule

Commit examples, not real values.

Commit:

```
terraform.tfvars.example
backend.hcl.example
```

Do not commit:

```
terraform.tfvars
backend.hcl
*.auto.tfvars
*.tfplan
tfplan
plan.txt
```

### Recommended `.gitignore`

```
# Terraform local files
.terraform/
*.tfstate
*.tfstate.*
crash.log
crash.*.log

# Local real inputs
terraform.tfvars
*.auto.tfvars
backend.hcl

# Plan artifacts
*.tfplan
tfplan
plan.txt
tfplan.txt

# Local proof packs with operational data
proof_*/
tmp_*/
```

### Practice

Run:

```bash
git status --ignored
```

Confirm real input files are ignored.

---

## E) SSM Parameter Store Pattern

Parameter Store is suitable for configuration values and secure strings. AWS describes Parameter Store as a way to store and retrieve configuration data, and `SecureString` parameters are encrypted using KMS. ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html))

Important: Terraform does **not** create the secret value in this lesson. That is intentional, so plaintext does not flow through Terraform variables/state/plan.

### Create a SecureString manually

```bash
aws ssm put-parameter \
  --name "/devops/lab65/demo/api-token" \
  --type "SecureString" \
  --value "replace-me-demo-token" \
  --overwrite
```

### Check it manually without storing plaintext

```bash
aws ssm get-parameter \
  --name "/devops/lab65/demo/api-token" \
  --with-decryption \
  --query 'Parameter.{Name:Name,Type:Type,Value:`REDACTED`}' \
  --output json
```

If you need to inspect the value for manual debugging, do not save it in logs, screenshots, shell history, or the proof pack.

### Terraform data source pattern

```hcl
data "aws_ssm_parameter" "demo_api_token" {
  name            = "/devops/lab65/demo/api-token"
  with_decryption = true
}
```

### Important warning

If you use the decrypted value in Terraform-managed resources, it can still flow into state depending on the resource argument. So the better pattern is often:

- Terraform creates IAM permission to read the parameter
- application/instance reads the value at runtime
- Terraform does **not** read the plaintext value

### Acceptance

- [ ]  You created a SecureString
- [ ]  You can read it manually with AWS CLI
- [ ]  You can explain why runtime retrieval can be safer than Terraform retrieval

---

## F) Secrets Manager Pattern

Use Secrets Manager for secrets that need stronger lifecycle management, especially rotation. AWS Secrets Manager supports rotation, including automatic rotation patterns for supported secrets. ([docs.aws.amazon.com](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html))

Important: the lab Terraform only knows the secret name and grants IAM access. The actual secret value is created separately with AWS CLI.

### Create a demo secret

```bash
aws secretsmanager create-secret \
  --name "/devops/lab65/demo/app-secret" \
  --secret-string '{"username":"demo","password":"replace-me"}'
```

### Read metadata only

```hcl
data "aws_secretsmanager_secret" "app" {
  name = "/devops/lab65/demo/app-secret"
}
```

### Safer pattern

Prefer referencing secret metadata/ARN in Terraform, not the plaintext value:

```hcl
output "app_secret_arn" {
  value       = data.aws_secretsmanager_secret.app.arn
  description = "ARN of the demo application secret"
}
```

Then the application role gets permission to read the secret at runtime.

### Acceptance

- [ ]  Secret exists in Secrets Manager
- [ ]  Terraform can reference the ARN without printing the secret value
- [ ]  You can explain when Secrets Manager is better than Parameter Store

---

## G) IAM Runtime Access Pattern

Instead of passing secret values through Terraform, give the instance role permission to read only the required path.

### Example policy

```hcl
data "aws_iam_policy_document" "runtime_secret_read" {
  statement {
    sid    = "ReadLesson65SecureString"
    effect = "Allow"

    actions = [
      "ssm:GetParameter"
    ]

    # The role gets access to a named parameter, but Terraform never reads the plaintext SecureString.
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.demo_api_token_parameter_name}"
    ]
  }

  statement {
    sid    = "ReadLesson65Secret"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    # Secrets Manager ARNs include a random suffix, so the IAM resource uses the secret name prefix.
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.demo_app_secret_name}*"
    ]
  }
}
```

Attach this to the application/web role only if the app needs it.

### Principle

> Terraform grants access. The workload retrieves the secret.
> 

This keeps Terraform closer to access control and farther away from secret handling.

In this lab, `lab_65/terraform/modules/network/iam.tf` implements that pattern:

- the EC2 runtime role may read one SSM SecureString name
- the EC2 runtime role may read one Secrets Manager secret name
- Terraform outputs only names/metadata, not plaintext values

If the SSM parameter or Secrets Manager secret does not exist yet, `terraform apply` can still succeed because the IAM policy only grants access to ARN/path patterns. Runtime reads from the instance will fail until the secret exists.

For private EC2 instances without NAT, IAM access alone is not enough. The workload also needs a network path to AWS APIs: in this lab, interface VPC endpoints provide that path for Session Manager, SSM Parameter Store, Secrets Manager, and STS.

### Troubleshooting: IAM exists, but runtime read does not work

This lab exposed a useful case during the runtime read check.

At first, the EC2 role had permissions:

- `ssm:GetParameter`
- `secretsmanager:GetSecretValue`

Session Manager also worked: SSM commands reached the instance. But reading the secret from inside the instance hung or timed out.

The root cause was not IAM. The instance was in a private subnet:

- no public IP
- no NAT
- no internet egress

So the workload could not reach the AWS API endpoint `secretsmanager.eu-west-1.amazonaws.com`. Session Manager already had the `ssm`, `ssmmessages`, and `ec2messages` endpoints, so SSM access worked. Runtime secret retrieval also needed a `secretsmanager` endpoint. Diagnostic calls such as `sts:GetCallerIdentity` need a separate `sts` endpoint.

Lab fix:

```hcl
private_endpoint_services = var.enable_ssm_vpc_endpoints ? toset([
  "ssm",
  "ssmmessages",
  "ec2messages",
  "secretsmanager",
  "sts",
]) : toset([])
```

After that, `terraform apply` added only two resources:

```text
Plan: 2 to add, 0 to change, 0 to destroy.
```

Then runtime proof passed:

```json
{
  "ssm_parameter": {
    "Name": "/devops/lab65/demo/api-token",
    "Type": "SecureString",
    "Value": "REDACTED"
  },
  "secretsmanager_secret": {
    "Name": "/devops/lab65/demo/app-secret",
    "Value": "REDACTED"
  }
}
```

Rule:

> Runtime secret access = IAM permission + network path to AWS API + redacted logging.

If the network path exists but IAM is missing, AWS returns `AccessDenied`.

If IAM exists but the network path is missing, the request cannot reach AWS API and will timeout/hang.

---

## H) CI Secret Safety

Your CI pipeline must not print secrets.

### GitHub Actions rules

Do not:

```yaml
run: echo "$SECRET_VALUE"
```

Do:

```yaml
run: echo "Secret is configured: ${SECRET_VALUE:+yes}"
```

### Plan artifact discipline

Plan artifacts are operational data. They may include resource names, ARNs, internal DNS, and sometimes sensitive-shaped values. Treat them as review artifacts, not public documentation.

### Add a secret scan workflow or local tool

You can use a tool such as Gitleaks or equivalent secret scanning.

Example local command pattern:

```bash
gitleaks detect --source . --verbose

If you do not install Gitleaks, run:
git grep -nE '(password|token|secret|apikey|api_key|private_key)' -- ':!*.md'
```

### Acceptance

- [ ]  No real secrets in repo
- [ ]  Plan artifacts are not treated as public
- [ ]  CI does not echo secret values

---

## I) Practical Walkthrough

This walkthrough shows the full path without storing plaintext secrets in Git, state proofs, or CI artifacts.

### 1. Check Local Inputs

From the repository root:

```bash
git status --short --ignored -- \
  lessons/65-secrets-sensitive-data-and-safe-inputs/lab_65/terraform/envs/terraform.tfvars \
  lessons/65-secrets-sensitive-data-and-safe-inputs/lab_65/terraform/envs/backend.hcl \
  lessons/65-secrets-sensitive-data-and-safe-inputs/lab_65/terraform/backend-bootstrap/terraform.tfstate
```

Expected: real files are shown as ignored (`!!`).

### 2. Create Secret Values Outside Terraform

```bash
aws ssm put-parameter \
  --name "/devops/lab65/demo/api-token" \
  --type "SecureString" \
  --value "replace-me-demo-token" \
  --overwrite
```

```bash
aws secretsmanager create-secret \
  --name "/devops/lab65/demo/app-secret" \
  --secret-string '{"username":"demo","password":"replace-me"}'
```

If the secret already exists, use an update command or delete the old demo secret.

### 3. Apply Terraform

From `lab_65/terraform/envs`:

```bash
terraform init -backend-config=backend.hcl
terraform plan -no-color
terraform apply
```

Terraform should grant IAM access to secret names, but should not read plaintext values.

### 4. Check Outputs

```bash
terraform output -no-color
```

Expected: names/metadata are visible, but token/password values are not.

### 5. Check Runtime Read and Capture Redacted Proof

For SSM, save only redacted output:

```bash
aws ssm get-parameter \
  --name "/devops/lab65/demo/api-token" \
  --with-decryption \
  --query 'Parameter.{Name:Name,Type:Type,Value:`REDACTED`}' \
  --output json
```

For Secrets Manager, save metadata:

```bash
aws secretsmanager describe-secret \
  --secret-id "/devops/lab65/demo/app-secret" \
  --output json
```

Do not save `SecretString` in the proof pack.

---

## J) Drills

### Drill 1 — Accidental secret in tfvars

**Goal:** confirm that real local inputs do not enter Git.

1. In `lab_65/terraform/envs/terraform.tfvars`, temporarily add a fake value:

```hcl
lab65_fake_secret_for_ignore_test = "fake-token-do-not-use"
```

2. Verify the file is ignored:

```bash
git status --ignored
```

Expected: the real `terraform.tfvars` should appear under ignored files, not staged/untracked files.

3. Keep only the safe shape in `terraform.tfvars.example`:

```hcl
demo_api_token_parameter_name = "/devops/lab65/demo/api-token"
demo_app_secret_name          = "/devops/lab65/demo/app-secret"
```

**Do not:** commit `terraform.tfvars`, `backend.hcl`, `tfstate`, or `.terraform/`.

**Acceptance**

- [ ]  real `terraform.tfvars` is ignored
- [ ]  example file is committed
- [ ]  temporary fake value removed after the check
- [ ]  no real-looking secret enters Git

---

### Drill 2 — Sensitive output redaction

**Goal:** see that `sensitive = true` hides CLI output, but does not make the value safe in state.

1. In `lab_65/terraform/envs`, temporarily create `scratch-sensitive-output.tf`:

```hcl
output "drill_sensitive_demo" {
  description = "Temporary drill output. Do not keep this in the lab."
  value       = sensitive("fake-sensitive-output")
  sensitive   = true
}
```

1. Run:

```bash
terraform fmt
terraform plan -no-color
terraform apply
terraform output -no-color
terraform output -json
```

Expected:

- normal `terraform output` shows `<sensitive>`
- `terraform output -json` may still contain the value
- the value enters state even when CLI hides it

1. Delete `scratch-sensitive-output.tf`.
2. Run `terraform apply` to remove the temporary output from state.

**Do not:** use this pattern for real passwords/API tokens. For a real secret, prefer runtime reads from SSM/Secrets Manager.

**Acceptance**

- [ ]  you saw CLI redaction behavior
- [ ]  you checked why `terraform output -json` and state need caution
- [ ]  temporary output removed from code and state
- [ ]  you can explain why `sensitive = true` is not secret storage

---

### Drill 3 — SSM runtime access

**Goal:** confirm that the workload role reads the secret value at runtime, not Terraform.

1. Check that the SecureString exists without printing plaintext:

```bash
aws ssm get-parameter \
  --name "/devops/lab65/demo/api-token" \
  --with-decryption \
  --query 'Parameter.{Name:Name,Type:Type,Value:`REDACTED`}' \
  --output json
```

If the parameter does not exist yet, create a demo value:

```bash
aws ssm put-parameter \
  --name "/devops/lab65/demo/api-token" \
  --type "SecureString" \
  --value "replace-me-demo-token" \
  --overwrite
```

1. Check the Terraform policy in `lab_65/terraform/modules/network/iam.tf`: the role should have `ssm:GetParameter` only for the required parameter path.
2. Check the private network path in `lab_65/terraform/modules/network/locals.tf`: endpoints should include `ssm`, `ssmmessages`, and `ec2messages`.
3. Save runtime proof from the instance only in redacted form. If you verify through SSM command, the script must print `Value: "REDACTED"`, not the real value.

Minimal proof without printing plaintext:

```bash
aws ssm get-parameter \
  --name "/devops/lab65/demo/api-token" \
  --with-decryption \
  --query 'Parameter.{Name:Name,Type:Type,Value:`REDACTED`}' \
  --output json > "$EVIDENCE_DIR/ssm-allowed-read-redacted.txt"
```

Negative test: temporarily test from a role/user without `ssm:GetParameter` and save only `AccessDenied`, not any secret value.

**Do not:** save raw output from `aws ssm get-parameter --with-decryption` without `--query ... Value:\`REDACTED\``.

**Acceptance**

- [ ]  allowed role can read
- [ ]  proof contains name/type, but not plaintext value
- [ ]  Terraform does not read or output the secret value
- [ ]  you can explain the difference between IAM permission and network path

---

### Drill 4 — Secrets Manager metadata only

**Goal:** separate metadata proof from runtime secret read.

1. Create the secret if it does not exist yet:

```bash
aws secretsmanager create-secret \
  --name "/devops/lab65/demo/app-secret" \
  --secret-string '{"username":"demo","password":"replace-me"}'
```

If the secret already exists, use an update command deliberately:

```bash
aws secretsmanager put-secret-value \
  --secret-id "/devops/lab65/demo/app-secret" \
  --secret-string '{"username":"demo","password":"replace-me"}'
```

2. Save metadata proof through `describe-secret`:

```bash
aws secretsmanager describe-secret \
  --secret-id "/devops/lab65/demo/app-secret" \
  --output json > "$EVIDENCE_DIR/secretsmanager-metadata.txt"
```

3. Runtime proof may use `GetSecretValue`, but output must be redacted. Store only this kind of shape in the proof pack:

```json
{
  "Name": "/devops/lab65/demo/app-secret",
  "Value": "REDACTED"
}
```

4. Check Terraform:

```bash
terraform output -no-color
terraform plan -no-color
```

Expected: Terraform shows only name/ARN/metadata, not `SecretString`.

**Do not:** save `SecretString` in evidence, logs, PR comments, or screenshots.

**Acceptance**

- [ ]  ARN/reference visible
- [ ]  metadata proof does not contain `SecretString`
- [ ]  runtime proof contains only `REDACTED`
- [ ]  you can explain runtime retrieval

---

### Drill 5 — CI/log leak check

**Goal:** prove that secret scanning catches leaks before merge.

1. Create a temporary file outside production code, for example `tmp-fake-leak.txt`.
2. Add a fake secret-like string. Use only a training fake, never a real secret:

```text
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
```

3. Run the scanner the same way CI does. If the workflow uses Gitleaks, local example:

```bash
gitleaks detect --source . --no-git --redact
```

If you are checking Git history:

```bash
gitleaks detect --source . --redact
```

1. Save fail output to `secret-scan-fail.txt`.
2. Delete `tmp-fake-leak.txt`.
3. Run the scan again and save clean output to `secret-scan-clean.txt`.

**Do not:** commit the fake leak to main. If a leak enters Git history, deleting the file is not enough: the scanner will keep seeing the secret in history.

**Acceptance**

- [ ]  scanner catches fake secret
- [ ]  clean state restored
- [ ]  you can explain why a leaked secret must be rotated/revoked even if the commit is deleted

---

## Proof Pack

For this lesson, capture:

```
evidence/
  classification-table.md
  git-status-ignored.txt
  local-checks.txt
  terraform-plan-redacted.txt
  terraform-output-redacted.txt
  ssm-allowed-read-redacted.txt
  secretsmanager-metadata.txt
  runtime-read-redacted.json
  no-secret-values-check.txt
  secret-scan-fail.txt
  secret-scan-clean.txt
```

Operational evidence can live in ignored `evidence/`. Do not commit real secret values in proofs.

---

## Common Pitfalls

- assuming `sensitive = true` keeps values out of state
- committing `terraform.tfvars`
- putting secrets in user-data
- printing secrets in GitHub Actions logs
- uploading raw plan artifacts without thinking who can access them
- using Terraform to read plaintext secrets when runtime access would be safer
- putting `backend.hcl` with real bucket/key details into public docs without intent

---

## Security Checklist

- real tfvars ignored
- examples committed instead of real inputs
- outputs marked sensitive where appropriate
- state backend treated as sensitive
- no secrets in plan artifacts
- no secrets in CI logs
- workloads read secrets at runtime via IAM
- no SSH/private keys baked into AMIs
- fake secret drills cleaned up

---

## Final Acceptance

Lesson 65 is complete if:

- [ ]  you can explain `sensitive` vs secret storage
- [ ]  no real secrets are committed
- [ ]  one SSM SecureString exists and is read by an authorized runtime role
- [ ]  one Secrets Manager secret is referenced by ARN only
- [ ]  CI/logs/artifacts do not expose secret values
- [ ]  practical walkthrough is completed with a redacted proof pack
- [ ]  at least 3 leak drills were completed and cleaned up

---

## Lesson Summary

- **What you learned:** sensitive data safety across Terraform, state, CI, and runtime.
- **What you practiced:** safe inputs, ignored tfvars, sensitive outputs, SSM SecureString, Secrets Manager metadata, secret scanning.
- **Operational focus:** Terraform should manage access and references, not transport plaintext secrets.
- **Why it matters:** a perfect deployment pipeline is still unsafe if it leaks credentials.

Core model of the lesson:

```text
Git should not store values.
Terraform should not read values.
CI should not print values.
AWS stores values.
The workload reads values at runtime through IAM.
```

Runtime access needs three conditions:

```text
Runtime secret access = IAM permission + network path to AWS API + redacted logging.
```

If IAM permission exists but the network path is missing, a private workload cannot reach AWS API and will timeout/hang.

If the network path exists but IAM permission is missing, AWS returns `AccessDenied`.

Using `terraform-plan-pr.yml` as an example:

- Git stores workflow logic and safe defaults
- GitHub variables can store non-secret config such as role ARN, bucket name, and region
- AWS SSM Parameter Store can store shared/internal config
- AWS SSM SecureString or Secrets Manager stores real secret values
- logs, artifacts, and PR comments should contain only metadata or `REDACTED`
