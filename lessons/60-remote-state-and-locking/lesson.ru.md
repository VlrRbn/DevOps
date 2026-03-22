# lesson_60

---

# Remote State & Locking (S3 Backend, Lockfile, Versioning, Safe Recovery)

**Date:** 2026-03-20

**Фокус:** перенести Terraform state с локального диска в S3 backend с locking, versioning, encryption и нормальной recovery-дисциплиной.

**Mindset:** никакой совместной Terraform-работы без remote state и locking.

---

## Зачем Этот Урок

Локальный state приемлем только пока у тебя:

- один терминал
- нет CI
- нет второго человека
- нет долгоживущего окружения

Как только один и тот же stack трогают из двух мест, local state превращается в операционный долг.

Remote state решает реальные проблемы:

- один source of truth
- backend-managed locking
- recoverable history через S3 versioning
- более безопасный CI и team workflow

---

## Что Должно Получиться

- поднять отдельный S3 backend для Terraform state
- мигрировать существующий env с local state на remote state
- проверить, что state object и lockfile реально работают
- доказать lock contention в двух терминалах
- понимать safe lock recovery и last-resort version restore
- понимать минимальную IAM-форму для локальной работы и CI

---

## Quick Path (30-45 min)

1. Создать backend bucket через bootstrap-конфиг на local state.
2. Добавить `backend "s3" {}` в один существующий Terraform root.
3. Создать `backend.hcl`.
4. Запустить `terraform init -backend-config=backend.hcl -migrate-state`.
5. Проверить remote state через:
   - `terraform state pull`
   - `aws s3 ls`
   - lock contention drill в двух терминалах
6. Снять proof pack.

---

## Prerequisites

- AWS credentials настроены локально
- Terraform уже работает хотя бы в одном env directory
- mindset из lesson 56-59 уже знаком:
  - repeatable runbooks
  - proof-pack discipline
- понимание, что Terraform state может содержать sensitive values

---

## Структура Урока

Рекомендуемая структура:

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

Важное разделение:

- `backend-bootstrap/` использует **только local state**
- реальные env потом используют **remote backend**

Не пытайся создать backend bucket через backend, которого ещё нет.

---

## Какую Модель State Надо Понять

Terraform state — это не просто техническая мелочь. Это operational artifact.

Он отвечает:

- что Terraform считает существующим
- какими resource IDs он управляет
- какие зависимости уже были разрешены
- что должно обновиться, замениться или удалиться дальше

Если state неверный, plan может быть неверным даже при правильном коде.

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

- [ ] state хранится в S3, а не только локально
- [ ] один существующий env мигрирован через `-migrate-state`
- [ ] bucket имеет versioning, encryption, public access block, TLS-only policy
- [ ] lock contention можно безопасно показать
- [ ] можешь объяснить, когда `force-unlock` допустим, а когда опасен
- [ ] можешь скачать старую версию state object для last-resort recovery
- [ ] понимаешь минимальную IAM-модель для CI/backend access

---

## A) Поднять Backend

### Rule

Backend-инфраструктура создаётся сначала и через **local state**.

Последовательность:

1. создать bucket
2. включить protection features
3. при необходимости создать legacy DynamoDB lock table
4. только потом мигрировать реальные env state в S3

### A1) Bootstrap config

Создай [main.tf](lessons/60-remote-state-and-locking/lab_60/terraform/backend-bootstrap/main.tf):

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

### Зачем этот конфиг

- `prevent_destroy = true`
  потеря backend — это инцидент
- versioning
  даёт recovery history, а не только текущее состояние
- encryption
  потому что state может содержать sensitive data
- public access block
  state никогда не должен быть public
- deny insecure transport
  не даём non-TLS requests

### A2) Применить bootstrap (создаёт bucket)

Узнай account ID:

```bash
aws sts get-caller-identity --query Account --output text
```

Шаблон bucket name:

```text
<prefix>-tfstate-<account-id>-<region>
"vlrrbn-tfstate-123456789012-eu-west-1"
```

Пример:

```bash
cd lessons/60-remote-state-and-locking/lab_60/terraform/backend-bootstrap
terraform init
terraform apply -var="state_bucket_name=vlrrbn-tfstate-123456789012-eu-west-1"
```

Опциональный legacy DynamoDB mode:

```bash
terraform apply \
  -var="state_bucket_name=vlrrbn-tfstate-123456789012-eu-west-1" \
  -var="enable_dynamodb_locking=true" \
  -var="dynamodb_table_name=terraform-state-locks"
```

### A3) Проверить backend bucket

```bash
aws s3api get-bucket-versioning --bucket vlrrbn-tfstate-123456789012-eu-west-1
aws s3api get-public-access-block --bucket vlrrbn-tfstate-123456789012-eu-west-1
aws s3api get-bucket-encryption --bucket vlrrbn-tfstate-123456789012-eu-west-1
```

Если AWS CLI как будто "висит", перезапусти bucket-check с явным region, без pager и с таймаутами:

```bash
aws s3api get-bucket-encryption \
  --bucket vlrrbn-tfstate-123456789012-eu-west-1 \
  --region eu-west-1 \
  --no-cli-pager \
  --cli-connect-timeout 5 \
  --cli-read-timeout 10
```

---

## B) Выбрать Режим Locking

### Recommended

Используй native S3 lockfile:

```hcl
use_lockfile = true
```

Это настраивается в backend-файле рабочего env, например в [backend.hcl](lessons/60-remote-state-and-locking/lab_60/terraform/envs/backend.hcl), а не в `backend-bootstrap/`.

Почему:

- меньше AWS-компонентов
- проще permissions
- легче объяснить и поддерживать

### Legacy / Optional

DynamoDB используй только если действительно нужно поддерживать старую схему:

```hcl
dynamodb_table = "terraform-state-locks"
```

Для этого трека основной mental model — native S3 locking.

---

## C) Подключить Remote Backend В Существующий Env

### C1) Добавить backend block

В Terraform root, который мигрируешь, добавь:

```hcl
terraform {
  backend "s3" {}
}
```

Почему:

- backend values нельзя подать обычными Terraform variables
- backend config передаётся на этапе `terraform init`

### C2) Создать backend.hcl

Пример [backend.hcl](lessons/60-remote-state-and-locking/lab_60/terraform/envs/backend.hcl):

```hcl
bucket       = "vlrrbn-tfstate-123456789012-eu-west-1"
key          = "lab60/dev/full/terraform.tfstate"
region       = "eu-west-1"
encrypt      = true
use_lockfile = true
```

Правило именования key:

```text
<project>/<environment>/<stack>/terraform.tfstate
```

Примеры:

- `lab56/prod/web/terraform.tfstate`
- `lab60/dev/full/terraform.tfstate`
- `shared/tools/backend-bootstrap/terraform.tfstate`

Никогда не используй один и тот же `key` для разных env.

### C3) Миграция state

Из target envs directory:

```bash
terraform init -backend-config=backend.hcl -migrate-state
```

Terraform спросит, переносить ли local state в backend.  
Для миграции нужно: **yes**.

`-migrate-state` используется для первого переезда с local state на remote backend.  
`-reconfigure` нужен потом, когда backend settings меняются, но state не мигрируется.

---

## D) Нормально Проверить Миграцию

### D1) Вытащить state через backend

```bash
terraform state pull | head -n 20
```

Смысл:

- Terraform теперь читает через backend
- доказываешь не просто наличие локального файла

### D2) Проверить, что object есть в S3

```bash
aws s3 ls s3://vlrrbn-tfstate-123456789012-eu-west-1/lab60/dev/full/terraform.tfstate
```

### D3) Опционально: перепроверить backend metadata

```bash
terraform init -reconfigure -backend-config=backend.hcl
```

Если backend уже настроен правильно, инициализация должна пройти чисто.

### D4) Local file sanity

Если раньше в `envs/` были local `terraform.tfstate` и `terraform.tfstate.backup`, после успешной миграции больше не считай их source of truth.

Теперь source of truth:

- remote backend object
- `terraform state pull`

---

## E) Locking Drills (Доказываем, Что Работает)

### Drill 1: Lock contention в двух терминалах

Терминал A:

```bash
terraform apply
```

Когда Terraform дойдёт до подтверждения, остановись. Не подтверждай.

Важно: этот drill требует non-empty plan.  
Если Terraform пишет `No changes`, сначала внеси одно безопасное временное изменение, чтобы terminal A реально держал lock на этапе подтверждения.

Терминал B:

```bash
terraform plan -lock-timeout=30s
```

Ожидаемо:

- terminal B упирается в lock-related message
- одновременно state держит только одна операция

### Drill 2: Понаблюдать lockfile

Пока terminal A ещё держит lock:

```bash
aws s3 ls s3://vlrrbn-tfstate-123456789012-eu-west-1/lab60/dev/full/
```

При native locking ты должен увидеть state object и lockfile примерно такого вида:

```text
terraform.tfstate
terraform.tfstate.tflock
```

### Drill 3: Safe lock recovery

Только если lock stale и ты точно знаешь, что активного Terraform процесса больше нет:

```bash
terraform force-unlock <LOCK_ID>
```

Безопасно:

- твой процесс упал
- CI job уже мёртв
- второй оператор точно ничего не крутит

Опасно:

- ты просто спешишь
- другой apply ещё может идти
- ты не проверил, чей это lock

Неправильный `force-unlock` может привести к concurrent state corruption.

---

## F) Versioning Drill (Recovery Mindset)

Versioning нужен не для casual rollback.  
Он нужен для last-resort recovery и расследования.

### F1) Посмотреть versions

```bash
aws s3api list-object-versions \
  --bucket vlrrbn-tfstate-123456789012-eu-west-1 \
  --prefix lab60/dev/full/terraform.tfstate
```

### F2) Скачать старую версию

```bash
aws s3api get-object \
  --bucket vlrrbn-tfstate-123456789012-eu-west-1 \
  --key lab60/dev/full/terraform.tfstate \
  --version-id <VERSION_ID> \
  /tmp/terraform.tfstate.old
```

### F3) Посмотреть, а не слепо подменять

```bash
jq '.serial, .lineage, .resources | length' /tmp/terraform.tfstate.old
```

Почему это важно:

- старая state-версия может уже не соответствовать реальной инфраструктуре
- восстановление state — это incident-level action

---

## G) CI + IAM Minimum Shape (Awareness Section)

Для S3 backend с native lockfile CI/backend access обычно требует:

- `s3:ListBucket`
- `s3:GetObject`
- `s3:PutObject`
- `s3:DeleteObject`

Почему важен `DeleteObject`:

- native lockfile надо удалять после успешной операции

Если используешь DynamoDB locking, добавь:

- `dynamodb:DescribeTable`
- `dynamodb:GetItem`
- `dynamodb:PutItem`
- `dynamodb:DeleteItem`

Правила:

- никаких static keys в backend config
- использовать environment credentials, AWS profile или OIDC-backed CI role
- помнить, что backend config values могут оказаться под `.terraform/`

---

## H) Normal Operator Runbook

Когда remote backend уже включён, нормальный Terraform flow становится таким:

1. `terraform init` с настроенным backend
2. `terraform plan`
3. `terraform apply`
4. если словил lock error:
   - сначала проверить active process
   - только потом думать про timeout или `force-unlock`
5. если случился state incident:
   - смотреть текущий remote state
   - смотреть старые S3 versions
   - восстанавливать аккуратно, а не вслепую

Смысл remote state не только в хранении.  
Смысл — в безопасной работе под concurrency.

---

## Proof Pack (Must-have Evidence)

Подробный guide по сбору:

- [proof-pack.ru.md](lessons/60-remote-state-and-locking/proof-pack.ru.md)

- output bootstrap apply
- output проверки versioning/encryption/public-access-block
- успешный `terraform init -migrate-state`
- заголовок вывода `terraform state pull`
- `aws s3 ls`, где виден remote state object
- output lock contention из второго терминала
- output `list-object-versions`

---

## Common Pitfalls

- создавать backend bucket через backend, которого ещё нет
- использовать один `key` для нескольких env
- продолжать доверять local `terraform.tfstate` после миграции
- использовать `force-unlock`, не проверив active operations
- считать старую S3 version готовым instant rollback

---

## Final Acceptance

- [ ] backend bucket существует и имеет versioning, encryption, public access block
- [ ] один env успешно мигрирован в S3 backend
- [ ] `terraform state pull` работает через remote backend
- [ ] S3 object существует по ожидаемому `bucket + key`
- [ ] lock contention воспроизведён в двух терминалах
- [ ] ты можешь объяснить safe vs unsafe `force-unlock`
- [ ] ты можешь скачать и посмотреть старую state version

---

## Security Checklist

- backend bucket private
- TLS-only bucket policy включён
- state encryption включён
- backend IAM минимально необходимый
- backend secrets не хардкодятся
- state рассматривается как sensitive operational data

---

## Lesson Summary

Lesson 60 — где Terraform state становится операционно корректным:

- remote вместо local
- locked вместо race-condition
- versioned вместо fragile
- recoverable вместо guess-based
