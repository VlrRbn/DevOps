# Proof Pack Урока 65

Артефакты лучше хранить вне Git или в ignored-папке `evidence/`. Реальные значения секретов не коммитим.

## Что сохранить

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

## Примеры команд

Из `lab_65/terraform/envs`:

```bash
export EVIDENCE_DIR="../../../evidence/l65-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
export EVIDENCE_DIR="$(realpath "$EVIDENCE_DIR")"
```

```bash
git status --ignored > "$EVIDENCE_DIR/git-status-ignored.txt"
terraform plan -no-color > "$EVIDENCE_DIR/terraform-plan-redacted.txt"
terraform output -no-color > "$EVIDENCE_DIR/terraform-output-redacted.txt"

aws secretsmanager describe-secret \
  --secret-id "/devops/lab65/demo/app-secret" \
  --output json > "$EVIDENCE_DIR/secretsmanager-metadata.txt"
```

Создай classification table без секретных значений:

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

Для SSM сохраняй только редактированное значение:

```bash
aws ssm get-parameter \
  --name "/devops/lab65/demo/api-token" \
  --with-decryption \
  --query 'Parameter.{Name:Name,Type:Type,Value:`REDACTED`}' \
  --output json > "$EVIDENCE_DIR/ssm-allowed-read-redacted.txt"
```

Для runtime proof можно читать реальные значения на instance, но сохранять только redacted JSON:

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

Проверь, что proof pack не содержит demo plaintext values:

```bash
if grep -RIlE 'replace-me-demo-token|replace-me|SecretString|password' "$EVIDENCE_DIR"; then
  echo "Potential secret-like pattern found; inspect evidence files locally." \
    > "$EVIDENCE_DIR/no-secret-values-check.txt"
else
  echo "No demo plaintext secret patterns found in evidence files." \
    > "$EVIDENCE_DIR/no-secret-values-check.txt"
fi
```

Ожидаемо: `no-secret-values-check.txt` сообщает, что demo plaintext secret patterns не найдены.

## Критерии успеха

- реальные `terraform.tfvars` и `backend.hcl` игнорируются
- в Git идут examples, а не реальные inputs
- outputs показывают metadata, а не значения секретов
- proof artifacts не содержат plaintext-секретов
- Secrets Manager metadata proof использует `describe-secret`
- runtime proof может использовать `get-secret-value`, но сохраняет только `REDACTED`, а не secret value
- приватный runtime имеет и IAM permission, и network path через VPC endpoints
- secret scanner падает на fake leak и проходит после cleanup
