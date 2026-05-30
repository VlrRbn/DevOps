# Proof Pack Урока 66

Этот proof pack нужен, чтобы показать: module contract реально работает, а ошибки контракта понятны до `apply`.

Запускать из:

```bash
cd lessons/66-module-contracts-and-interface-guarantees/lab_66/terraform/envs
```

Создать папку evidence:

```bash
export EVIDENCE_DIR="../../../evidence/l66-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
```

## 1. Базовая Проверка

```bash
terraform fmt -check -recursive .. > "$EVIDENCE_DIR/fmt.txt" 2>&1
terraform validate -no-color > "$EVIDENCE_DIR/validate.txt" 2>&1
terraform plan -no-color > "$EVIDENCE_DIR/baseline-plan.txt" 2>&1
```

Ожидаемо:

- fmt проходит
- validate проходит
- plan читаемый
- baseline plan может показывать creates, если lab ещё не применена
- временный `contract-drill.auto.tfvars` отсутствует
- plaintext secret values не попадают в outputs

## 2. Неправильный Project Name

```bash
cat > contract-drill.auto.tfvars <<'EOF'
project_name = "LAB_66"
EOF

terraform plan -no-color > "$EVIDENCE_DIR/bad-project-name-plan.txt" 2>&1 || true
rm -f contract-drill.auto.tfvars
```

Ожидаемо:

- Terraform отклоняет значение до `apply`.
- Ошибка объясняет формат lowercase kebab-style.

## 3. Слишком Мало Private Subnets

```bash
cat > contract-drill.auto.tfvars <<'EOF'
private_subnet_cidrs = ["10.30.11.0/24"]
EOF

terraform plan -no-color > "$EVIDENCE_DIR/one-subnet-plan.txt" 2>&1 || true
rm -f contract-drill.auto.tfvars
```

Ожидаемо:

- Terraform отклоняет значение до `apply`.
- Ошибка объясняет, что нужно минимум два private subnet CIDR.

## 4. Слишком Много Private Subnets

```bash
cat > contract-drill.auto.tfvars <<'EOF'
private_subnet_cidrs = [
  "10.30.11.0/24",
  "10.30.12.0/24",
  "10.30.13.0/24",
  "10.30.14.0/24",
  "10.30.15.0/24",
  "10.30.16.0/24",
  "10.30.17.0/24",
]
EOF

terraform plan -no-color > "$EVIDENCE_DIR/too-many-subnets-plan.txt" 2>&1 || true
rm -f contract-drill.auto.tfvars
```

Ожидаемо:

- Terraform отклоняет значение до `apply`.
- Ошибка объясняет поддерживаемый контракт 2-6 subnet CIDRs.

## 5. Неправильный AMI ID

```bash
cat > contract-drill.auto.tfvars <<'EOF'
web_ami_id = "ubuntu-latest"
EOF

terraform plan -no-color > "$EVIDENCE_DIR/bad-ami-id-plan.txt" 2>&1 || true
rm -f contract-drill.auto.tfvars
```

Ожидаемо:

- Terraform отклоняет значение до `apply`.
- Ошибка объясняет ожидаемую форму AMI ID.

## 6. Пустое Значение Tag

```bash
cat > contract-drill.auto.tfvars <<'EOF'
common_tags = {
  Owner = ""
}
EOF

terraform plan -no-color > "$EVIDENCE_DIR/empty-tag-plan.txt" 2>&1 || true
rm -f contract-drill.auto.tfvars
```

Ожидаемо:

- Terraform отклоняет пустые tag values.

## 7. Попытка Перезаписать Reserved Tag

```bash
cat > contract-drill.auto.tfvars <<'EOF'
common_tags = {
  Project = "manual"
}
EOF

terraform plan -no-color > "$EVIDENCE_DIR/reserved-tag-plan.txt" 2>&1 || true
rm -f contract-drill.auto.tfvars
```

Ожидаемо:

- Terraform отклоняет попытку caller перезаписать reserved governance tags.

## 8. Output Contract Review

Создать:

```bash
cat > "$EVIDENCE_DIR/output-contract.md" <<'EOF'
| Output | Consumer | Stability |
|---|---|---|
| alb_dns_name | SSM proxy curl tests | stable |
| web_asg_name | release workflows | stable |
| web_tg_arn | health/drift workflows | stable |
| ssm_vpc_endpoint_ids | private runtime proof | stable map keyed by service |
EOF
```

Ожидаемо:

- У каждого public output есть понятный consumer.
- Output не раскрывает whole resource или plaintext secret value.

## 9. Финальный Baseline Plan

```bash
terraform plan -no-color > "$EVIDENCE_DIR/baseline-plan-after-fixes.txt" 2>&1
```

Ожидаемо:

- временный drill файл удалён
- baseline plan читаемый
- baseline plan может показывать creates, если lab ещё не применена
- module contract отклоняет invalid inputs до изменения инфраструктуры

## 10. CI Contract Gate

Проверить GitHub Actions run для `.github/workflows/lesson66-contract-tests.yml`.

Ожидаемо:

- Terraform formatting прошёл.
- Init без backend и validate прошли.
- Негативные input drills упали с ожидаемыми validation messages.
- AWS credentials не нужны.

## 11. Decision

Создать:

```bash
cat > "$EVIDENCE_DIR/decision.txt" <<'EOF'
Decision: PASS
Lesson: 66-module-contracts-and-interface-guarantees

Evidence:
- variable validation rejects invalid caller input
- ASG preconditions document runtime assumptions
- outputs are stable and documented
- reserved governance tags cannot be overridden by callers
- breaking/non-breaking module change policy is documented
- CI contract gate checks the same negative input behavior
EOF
```
