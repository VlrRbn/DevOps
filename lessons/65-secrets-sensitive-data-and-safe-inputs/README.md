# Lesson 65 - Secrets, Sensitive Data & Safe Inputs

This lesson continues the Terraform operations track after drift detection.

## Goal

Keep secret-like values out of Git, Terraform outputs, plan artifacts, and CI logs. Terraform should manage access and references; workloads should read secret values at runtime.

## Files

- `lesson.en.md` - English lesson
- `lesson.ru.md` - Russian lesson
- `proof-pack.en.md` - evidence checklist
- `proof-pack.ru.md` - evidence checklist in Russian
- `ci/secrets-scan.yml` - GitHub Actions example for secret scanning
- `lab_65/terraform/envs/terraform.tfvars.example` - safe input example
- `lab_65/terraform/envs/backend.hcl.example` - safe backend example

## Local-Only Files

The real files below are intentionally ignored inside `lab_65/terraform/envs/`:

- `terraform.tfvars`
- `backend.hcl`
- `*.auto.tfvars`
- `*.tfplan`
- `plan.txt`
- `tfplan.txt`

## Lab Pattern

The lab grants the EC2 runtime role permission to read:

- one SSM SecureString parameter name
- one Secrets Manager secret name

Terraform does not read or output plaintext secret values.

For private EC2 instances, runtime access also needs a network path to AWS APIs. The lab creates interface VPC endpoints for Session Manager, SSM Parameter Store, Secrets Manager, and STS.

Terraform also does not create those secret values. Create demo values manually with AWS CLI before testing runtime reads:

```bash
aws ssm put-parameter \
  --name "/devops/lab65/demo/api-token" \
  --type "SecureString" \
  --value "replace-me-demo-token" \
  --overwrite

aws secretsmanager create-secret \
  --name "/devops/lab65/demo/app-secret" \
  --secret-string '{"username":"demo","password":"replace-me"}'
```

Do not save plaintext secret values in logs, screenshots, PR comments, or proof artifacts. Runtime proof should be redacted, for example:

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

## Evidence

Operational evidence belongs in ignored `evidence/` folders. Use the proof-pack files for the exact checklist:

- `proof-pack.en.md`
- `proof-pack.ru.md`
