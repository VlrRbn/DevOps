# Lesson 65 Proof Pack

Store proof artifacts outside Git or in an ignored `evidence/` folder. Do not commit real secret values.

## Required Evidence

```text
evidence/
  classification-table.md
  git-status-ignored.txt
  terraform-plan-redacted.txt
  terraform-output-redacted.txt
  ssm-allowed-read-redacted.txt
  secretsmanager-metadata.txt
  runtime-read-redacted.json
  no-secret-values-check.txt
  secret-scan-fail.txt
  secret-scan-clean.txt
```

## Capture Commands

From `lab_65/terraform/envs`:

```bash
export EVIDENCE_DIR="../../../evidence/l65-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
export EVIDENCE_DIR="$(realpath "$EVIDENCE_DIR")"
```

Use these commands as examples:

```bash
git status --ignored > "$EVIDENCE_DIR/git-status-ignored.txt"
terraform plan -no-color > "$EVIDENCE_DIR/terraform-plan-redacted.txt"
terraform output -no-color > "$EVIDENCE_DIR/terraform-output-redacted.txt"

aws secretsmanager describe-secret \
  --secret-id "/devops/lab65/demo/app-secret" \
  --output json > "$EVIDENCE_DIR/secretsmanager-metadata.txt"
```

Create a classification table without secret values:

```bash
cat > "$EVIDENCE_DIR/classification-table.md" <<'EOF'
| Value | Classification | Current location | Target location |
|---|---|---|---|
| aws_region | public config | tfvars | tfvars |
| vpc_cidr | internal config | tfvars | tfvars |
| public_subnet_cidrs | internal config | tfvars | tfvars |
| web_ami_id | internal config / sensitive | tfvars | tfvars |
| alb_dns_name | internal config / sensitive | output | output |
| tf_plan_role_arn | sensitive | output | GitHub Actions variable |
| demo_api_token_parameter_name | internal config | tfvars/output | SSM Parameter Store name |
| demo_app_secret_name | internal config | tfvars/output | Secrets Manager name |
EOF
```

For SSM reads, redact the returned value before saving:

```bash
aws ssm get-parameter \
  --name "/devops/lab65/demo/api-token" \
  --with-decryption \
  --query 'Parameter.{Name:Name,Type:Type,Value:`REDACTED`}' \
  --output json > "$EVIDENCE_DIR/ssm-allowed-read-redacted.txt"
```

For runtime proof, the instance may read real values, but the saved evidence must be redacted JSON:

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

Check that the proof pack does not contain demo plaintext values:

```bash
if grep -RIlE 'replace-me-demo-token|replace-me|SecretString|password' "$EVIDENCE_DIR"; then
  echo "Potential secret-like pattern found; inspect evidence files locally." \
    > "$EVIDENCE_DIR/no-secret-values-check.txt"
else
  echo "No demo plaintext secret patterns found in evidence files." \
    > "$EVIDENCE_DIR/no-secret-values-check.txt"
fi
```

Expected: `no-secret-values-check.txt` says no demo plaintext secret patterns were found.

## Pass Criteria

- real `terraform.tfvars` and `backend.hcl` are ignored
- examples are committed instead of real inputs
- outputs expose metadata only
- secret values are not present in proof artifacts
- Secrets Manager metadata proof uses `describe-secret`
- runtime proof may use `get-secret-value`, but stores only `REDACTED`, not the secret value
- private runtime has both IAM permission and a network path through VPC endpoints
- secret scanner can fail on a fake leak and pass after cleanup
