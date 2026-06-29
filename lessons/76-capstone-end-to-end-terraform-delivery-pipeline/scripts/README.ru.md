# Скрипты урока 76

Эта папка содержит вспомогательные скрипты для локальных проверок, review evidence, runtime health evidence и incident recovery evidence.

## Скрипты

| Скрипт | Назначение | Меняет инфраструктуру/state? |
| --- | --- | --- |
| `run-local-checks.sh` | Запускает безопасные локальные проверки. | Нет |
| `write-terraform-env-files.sh` | Генерирует временные `backend.hcl` и `terraform.auto.tfvars` для CI. | Нет |
| `promotion-evidence-template.sh` | Генерирует валидный JSON promotion evidence. | Нет |
| `reviewer-note-template.sh` | Генерирует Markdown reviewer note из `risk-decision.json`. | Нет |
| `runtime-health-check.sh` | Собирает read-only ALB/ASG/CloudWatch runtime evidence. | Нет |
| `state-snapshot.sh` | Сохраняет current state и plan в local evidence перед recovery. | Нет |
| `post-incident-check.sh` | Сохраняет post-incident plan status. | Нет |
| `list-state-versions.sh` | Показывает S3 versions для Terraform state key. | Нет |
| `incident-decision-template.sh` | Генерирует incident decision note template. | Нет |
| `collect-capstone-proof.sh` | Копирует known evidence в одну timestamped папку. | Нет |
| `summarize-capstone.sh` | Генерирует `capstone-review-summary.md` из evidence. | Нет |

## Локальные проверки

Запуск из корня репозитория:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
```

Опциональные проверки:

```bash
RUN_OPA=true lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
RUN_TERRAFORM=true lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
```

## Review helpers

## CI helper

```bash
AWS_REGION=eu-west-1 \
TF_STATE_BUCKET=example-tfstate \
TF_WEB_AMI_ID=ami-0123456789abcdef0 \
TF_SSM_PROXY_AMI_ID=ami-0123456789abcdef0 \
TF_GITHUB_OWNER=VlrRbn \
TF_GITHUB_REPO=DevOps \
TF_GITHUB_OIDC_PROVIDER_ARN=arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/write-terraform-env-files.sh dev
```

Скрипт нужен для GitHub Actions: `backend.hcl` и `terraform.auto.tfvars` не хранятся в Git, поэтому clean runner должен создать их перед `terraform init`.

## Review helpers

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/promotion-evidence-template.sh \
  l76-demo \
  dev \
  "$(git rev-parse HEAD)" \
  "https://github.com/OWNER/REPO/actions/runs/123456789" \
  > /tmp/promotion-evidence-stage.json
```

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/reviewer-note-template.sh \
  /tmp/l76-risk/risk-decision.json \
  > /tmp/l76-reviewer-note.md
```

## Runtime и incident evidence

Эти команды читают AWS/Terraform данные и пишут local evidence bundles:

```bash
AWS_REGION=eu-west-1 lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/runtime-health-check.sh dev
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/state-snapshot.sh dev
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/post-incident-check.sh dev
```

## Proof pack helpers

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/collect-capstone-proof.sh dev
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/summarize-capstone.sh lessons/76-capstone-end-to-end-terraform-delivery-pipeline/evidence/<folder>
```

`collect-capstone-proof.sh` копирует только known files. Он не делает redaction автоматически. Проверь output перед sharing или commit.

Он также не ищет outputs в `/tmp`. Если ты запускал `security-policy.sh`, `cost-policy.sh` или `risk-classifier.sh` с `OUT_DIR=/tmp/...`, скопируй эти директории в evidence folder перед запуском `summarize-capstone.sh`.

## Безопасность

- Скрипты не запускают `terraform apply` или `terraform destroy`.
- Runtime/state scripts могут вызывать AWS APIs и Terraform read-only commands.
- Generated evidence может содержать ARNs, account IDs, DNS names, IPs и operational metadata.
- Не коммить raw evidence без intentional redaction.
