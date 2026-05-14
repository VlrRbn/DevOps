# Урок 65. Секреты, чувствительные данные и безопасные входные значения

**Дата:** 2026-05-13

**Фокус:** не дать секретам утечь через Terraform-код, state, plan-артефакты, CI-логи, Terraform variables и outputs.

**Подход:** управление секретами это не только “куда положить пароль”, а “где это значение может случайно появиться”.

---

## Зачем этот урок

После урока 64 workflow умеет находить drift между Terraform-кодом и реальным состоянием AWS.

Теперь следующий риск другой:

- секреты в `terraform.tfvars`
- чувствительные значения в state
- plan-артефакты, загруженные в CI
- значения из outputs, попавшие в логи
- backend config, попавший в `.terraform/`
- пароли, переданные через user-data
- случайные коммиты с секретами

Terraform может скрывать чувствительные значения в выводе CLI, но `sensitive = true` **не означает**, что значение автоматически отсутствует в state. В документации Terraform отдельно описаны sensitive variables, которые скрываются в выводе CLI, и ephemeral values для поддерживаемых случаев, где значение не должно попадать в state и plan-файлы. ([HashiCorp Developer](https://developer.hashicorp.com/terraform/language/block/variable))

Этот урок про безопасную модель мышления: Terraform должен управлять доступом и ссылками, а не протаскивать открытые значения секретов через pipeline.

---

## Что должен уметь после урока

- понимать, что Terraform `sensitive` защищает и чего не защищает
- находить места, где секреты могут утечь:
  - код
  - tfvars
  - state
  - plan-артефакты
  - CI-логи
  - outputs
  - user-data
- переносить значения, похожие на секреты, в более безопасные хранилища:
  - SSM Parameter Store
  - AWS Secrets Manager
- проектировать Terraform variables и outputs с безопасными значениями по умолчанию
- добавлять локальные и CI-проверки против случайных коммитов с секретами
- проходить упражнения, которые доказывают, что секреты не появляются там, где их быть не должно

---

## Быстрый маршрут

1. Классифицируй все значения в lab:
   - public config
   - internal config
   - sensitive
   - secret
2. Добавь `sensitive = true` там, где это уместно.
3. Убери значения, похожие на секреты, из `.tfvars`, которые попадают в Git.
4. Сохрани одно значение в SSM Parameter Store.
5. Сохрани одно значение в Secrets Manager.
6. Докажи:
   - значение не попало в Git
   - значение не выводится в outputs
   - CI-артефакты его не раскрывают
   - state считается чувствительным
7. Добавь secret scanning в проверку качества.

---

## Требования

- урок 60: remote state и locking
- урок 63: PR plan pipeline
- урок 64: drift detection workflow
- настроенный AWS CLI
- доступный GitHub Actions workflow
- базовое понимание IAM

---

## Структура

```text
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

## A) Модель утечки секретов

Значение может утечь через большее количество мест, чем обычно ожидаем.

| Место | Риск |
| --- | --- |
| `.tf` files | остаются в истории Git |
| `.tfvars` | часто случайно коммитят |
| Terraform state | может содержать чувствительные аргументы ресурсов |
| plan-файлы | могут содержать операционные детали |
| CI-артефакты | доступны людям с доступом к репозиторию |
| outputs | легко попадают в логи |
| user-data | может быть виден через instance metadata / cloud-init history |
| shell history | локальная утечка |
| GitHub Actions logs | случайный `echo` |

Важное правило:

> Если значение входит в Terraform, считай, что оно может попасть в state, пока не доказано обратное.

Terraform S3 backend хранит state как объект в S3 по настроенному bucket/key path, поэтому bucket с remote state нужно считать чувствительной инфраструктурой, а не “просто хранилищем”. ([HashiCorp Developer](https://developer.hashicorp.com/terraform/language/backend/s3))

### Безопасный поток секрета

Цель этого урока — держать plaintext secret вне Terraform:

```text
Developer / operator
  -> создаёт secret value в AWS SSM или Secrets Manager
  -> Terraform выдаёт IAM role право читать конкретный secret name/path
  -> EC2 instance или приложение читает secret на runtime
  -> proof pack сохраняет только metadata и REDACTED-результат
```

Неправильный поток:

```text
secret value
  -> terraform.tfvars
  -> Terraform resource argument
  -> state / plan / CI artifact
```

---

## B) Классификация: config, sensitive, secret

Используй эту таблицу классификации.

| Тип | Пример | Безопасно в Git? | Безопасно в state? | Комментарий |
| --- | --- | --- | --- | --- |
| Public config | region, project name | yes | yes | обычный input |
| Internal config | VPC CIDR, subnet CIDRs | usually | yes | не secret, но операционные данные |
| Sensitive | account IDs, ARNs, internal DNS | sometimes | usually | не публикуй без причины |
| Secret | passwords, tokens, private keys | no | avoid | используй хранилище секретов |

### Практика

Создай в уроке таблицу минимум на 10 значений из lab:

```markdown
| Value | Classification | Current location | Target location |
|---|---|---|---|
| AWS region | public config | tfvars | tfvars |
| ALB DNS | internal config | output | output |
| Telegram token | secret | not used here | Secrets Manager |
| DB password | secret | not used here | Secrets Manager |
```

Критерий: уметь объяснить, почему каждое значение попало именно в эту категорию.

### Пример классификации для lab 65

Важно: **не secret** не значит **public**.

| Значение | Классификация | Почему |
| --- | --- | --- |
| `aws_region` | public config | регион сам по себе не раскрывает секрет |
| `project_name` | public config | имя учебного проекта не секрет |
| `vpc_cidr` | internal config | часть сетевой схемы |
| `public_subnet_cidrs` | internal config | тоже часть сетевой схемы, несмотря на слово `public` |
| `web_ami_id` | internal config / sensitive | может раскрывать account/region-specific build |
| `ssm_proxy_private_ip` | internal config / sensitive | внутренний адрес инфраструктуры |
| `alb_dns_name` | internal config / sensitive | внутренний endpoint |
| `tf_plan_role_arn` | sensitive | раскрывает IAM role ARN для CI |
| `demo_api_token_parameter_name` | internal config | это location секрета, не value |
| `demo_app_secret_name` | internal config | это location секрета, не value |

---

## C) Terraform `sensitive`

### Пример variable

```hcl
variable "admin_password" {
  type        = string
  description = "Example secret value for lesson 65. Do not commit real secrets."
  sensitive   = true
}
```

### Пример output

```hcl
output "admin_password_demo" {
  value     = var.admin_password
  sensitive = true
}
```

Это не позволяет выводу CLI показать значения напрямую, но это не значит, что реальные секреты можно спокойно передавать через Terraform. Документация Terraform описывает `sensitive` как скрытие значения в выводе CLI, а ephemeral values как механизм для поддерживаемых случаев, где значения должны быть исключены из state и plan-файлов. ([HashiCorp Developer](https://developer.hashicorp.com/terraform/language/block/variable))

### Критерии

- [ ]  Ты можешь объяснить, что защищает `sensitive = true`
- [ ]  Ты можешь объяснить, чего оно **не** защищает
- [ ]  Ты не считаешь это хранилищем секретов

### Плохой и хороший паттерн

Плохо: секретное значение проходит через Terraform input.

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

Почему плохо: `sensitive = true` скроет вывод, но value всё равно может оказаться в state или plan.

Хорошо: Terraform знает только имя секрета и выдаёт runtime-доступ.

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

Плохо: output раскрывает secret value.

```hcl
output "app_secret_string" {
  value = aws_secretsmanager_secret_version.app.secret_string
}
```

Хорошо: output показывает только metadata.

```hcl
output "demo_app_secret_name" {
  value       = var.demo_app_secret_name
  description = "Secret name only. This is metadata, not the secret value."
}
```

---

## D) Безопасные входные файлы

### Правило

Коммить примеры, а не реальные значения.

Коммитить:

```text
terraform.tfvars.example
backend.hcl.example
```

Не коммитить:

```text
terraform.tfvars
backend.hcl
*.auto.tfvars
*.tfplan
tfplan
plan.txt
```

### Рекомендуемый `.gitignore`

```gitignore
# Локальные файлы Terraform
.terraform/
*.tfstate
*.tfstate.*
crash.log
crash.*.log

# Реальные локальные inputs
terraform.tfvars
*.auto.tfvars
backend.hcl

# Plan-артефакты
*.tfplan
tfplan
plan.txt
tfplan.txt

# Локальные proof packs с операционными данными
proof_*/
tmp_*/
```

### Практика

Запусти:

```bash
git status --ignored
```

Подтверди, что реальные input-файлы игнорируются.

---

## E) Паттерн SSM Parameter Store

Parameter Store подходит для конфигурационных значений и secure strings. AWS описывает Parameter Store как способ хранить и получать конфигурационные данные, а `SecureString` parameters шифруются через KMS. ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html))

Важно: Terraform **не создаёт значение секрета** в этом уроке. Это сделано намеренно, чтобы plaintext не проходил через Terraform variables, state и plan.

### Создать SecureString вручную

```bash
aws ssm put-parameter \
  --name "/devops/lab65/demo/api-token" \
  --type "SecureString" \
  --value "replace-me-demo-token" \
  --overwrite
```

### Проверить вручную без сохранения plaintext

```bash
aws ssm get-parameter \
  --name "/devops/lab65/demo/api-token" \
  --with-decryption \
  --query 'Parameter.{Name:Name,Type:Type,Value:`REDACTED`}' \
  --output json
```

Если тебе нужно увидеть значение для ручной отладки, не сохраняй его в logs, screenshots, shell history или proof pack.

### Паттерн Terraform data source

```hcl
data "aws_ssm_parameter" "demo_api_token" {
  name            = "/devops/lab65/demo/api-token"
  with_decryption = true
}
```

### Важное предупреждение

Если использовать расшифрованное значение в ресурсах, которыми управляет Terraform, оно всё ещё может попасть в state в зависимости от аргумента ресурса. Поэтому часто лучше такой паттерн:

- Terraform создаёт IAM-разрешение на чтение parameter
- приложение или instance читает значение во время выполнения
- Terraform **не** читает plaintext-значение

### Критерии

- [ ]  Ты создал SecureString
- [ ]  Ты можешь прочитать его вручную через AWS CLI
- [ ]  Ты можешь объяснить, почему чтение секрета на runtime может быть безопаснее чтения через Terraform

---

## F) Паттерн Secrets Manager

Secrets Manager используй для секретов, которым нужен более сильный lifecycle management, особенно rotation. AWS Secrets Manager поддерживает rotation, включая automatic rotation patterns для поддерживаемых секретов. ([docs.aws.amazon.com](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html))

Важно: Terraform в lab знает только имя секрета и выдаёт IAM access. Само значение секрета создаётся отдельно через AWS CLI.

### Создать demo secret

```bash
aws secretsmanager create-secret \
  --name "/devops/lab65/demo/app-secret" \
  --secret-string '{"username":"demo","password":"replace-me"}'
```

### Читать только метаданные

```hcl
data "aws_secretsmanager_secret" "app" {
  name = "/devops/lab65/demo/app-secret"
}
```

### Более безопасный паттерн

Лучше ссылаться на метаданные или ARN секрета в Terraform, а не на plaintext-значение:

```hcl
output "app_secret_arn" {
  value       = data.aws_secretsmanager_secret.app.arn
  description = "ARN of the demo application secret"
}
```

Потом роль приложения получает разрешение читать secret на runtime.

### Критерии

- [ ]  Secret существует в Secrets Manager
- [ ]  Terraform может ссылаться на ARN без вывода значения секрета
- [ ]  Ты можешь объяснить, когда Secrets Manager лучше Parameter Store

---

## G) Паттерн IAM runtime access

Вместо передачи значений секретов через Terraform дай instance role разрешение читать только нужный path.

### Пример policy

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

Прикрепляй это к application/web role только если приложению реально нужен этот доступ.

### Принцип

> Terraform предоставляет доступ. The workload извлекает секрет.
>

Так Terraform остаётся ближе к управлению доступом и дальше от обработки секретных значений.

В этой lab `lab_65/terraform/modules/network/iam.tf` реализует этот паттерн:

- runtime-роль EC2 может читать один SSM SecureString name
- runtime-роль EC2 может читать один Secrets Manager secret name
- Terraform outputs показывают только имена/метаданные, а не plaintext-значения

Если SSM parameter или Secrets Manager secret ещё не существует, `terraform apply` всё равно может пройти, потому что IAM policy выдаёт доступ только к ARN/path patterns. Чтение с instance на runtime будет падать, пока secret не существует.

Для приватных EC2 без NAT одного IAM доступа недостаточно. Нужен ещё сетевой путь к AWS API: в этой lab его дают interface VPC endpoints для Session Manager, SSM Parameter Store, Secrets Manager и STS.

### Troubleshooting: IAM есть, но runtime read не работает

В этой lab при проверке runtime read всплыл полезный case.

Сначала у EC2 role были права:

- `ssm:GetParameter`
- `secretsmanager:GetSecretValue`

И Session Manager работал: SSM command доходил до instance. Но чтение секрета изнутри instance зависало или уходило в timeout.

Причина была не в IAM. Instance находился в private subnet:

- public IP нет
- NAT нет
- выхода в интернет нет

А значит, workload не мог дойти до AWS API endpoint `secretsmanager.eu-west-1.amazonaws.com`. Для Session Manager уже были endpoints `ssm`, `ssmmessages`, `ec2messages`, поэтому сам SSM-доступ работал. Но для runtime чтения секрета нужен был ещё `secretsmanager` endpoint. Для диагностического `sts:GetCallerIdentity` нужен отдельный `sts` endpoint.

Исправление в lab:

```hcl
private_endpoint_services = var.enable_ssm_vpc_endpoints ? toset([
  "ssm",
  "ssmmessages",
  "ec2messages",
  "secretsmanager",
  "sts",
]) : toset([])
```

После этого `terraform apply` добавил только два ресурса:

```text
Plan: 2 to add, 0 to change, 0 to destroy.
```

Затем runtime proof прошёл:

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

Правило:

> Runtime secret access = IAM permission + network path to AWS API + redacted logging.

Если есть network path, но нет IAM, AWS вернёт `AccessDenied`.

Если есть IAM, но нет network path, запрос не дойдёт до AWS API и будет timeout/hang.

---

## H) Безопасность секретов в CI

CI pipeline не должен печатать секреты.

### Правила GitHub Actions

Не делай так:

```yaml
run: echo "$SECRET_VALUE"
```

Делай так:

```yaml
run: echo "Secret is configured: ${SECRET_VALUE:+yes}"
```

### Аккуратная работа с plan-артефактами

Plan-артефакты это операционные данные. Они могут содержать имена ресурсов, ARNs, internal DNS и иногда значения, похожие на чувствительные. Относись к ним как к артефактам для review, а не как к публичной документации.

### Secret scan workflow или локальный инструмент

Можно использовать Gitleaks или похожий инструмент для поиска секретов.

Пример локальной команды:

```bash
gitleaks detect --source . --verbose

Если Gitleaks не установлен, запусти:
git grep -nE '(password|token|secret|apikey|api_key|private_key)' -- ':!*.md'
```

### Критерии

- [ ]  В репозитории нет реальных секретов
- [ ]  Plan-артефакты не считаются публичными
- [ ]  CI не печатает значения секретов

---

## I) Практический walkthrough

Этот walkthrough показывает полный путь без сохранения plaintext-секретов в Git, state proofs или CI artifacts.

### 1. Проверить локальные inputs

Из корня репозитория:

```bash
git status --short --ignored -- \
  lessons/65-secrets-sensitive-data-and-safe-inputs/lab_65/terraform/envs/terraform.tfvars \
  lessons/65-secrets-sensitive-data-and-safe-inputs/lab_65/terraform/envs/backend.hcl \
  lessons/65-secrets-sensitive-data-and-safe-inputs/lab_65/terraform/backend-bootstrap/terraform.tfstate
```

Ожидаемо: реальные файлы показаны как ignored (`!!`).

### 2. Создать secret values вне Terraform

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

Если secret уже существует, используй update-команду или удали старый demo secret.

### 3. Применить Terraform

Из `lab_65/terraform/envs`:

```bash
terraform init -backend-config=backend.hcl
terraform plan -no-color
terraform apply
```

Terraform должен выдавать IAM-доступ к secret names, но не должен читать plaintext values.

### 4. Проверить outputs

```bash
terraform output -no-color
```

Ожидаемо: видны имена/metadata, но не значения token/password.

### 5. Проверить runtime read и сохранить redacted proof

Для SSM сохраняй только redacted output:

```bash
aws ssm get-parameter \
  --name "/devops/lab65/demo/api-token" \
  --with-decryption \
  --query 'Parameter.{Name:Name,Type:Type,Value:`REDACTED`}' \
  --output json
```

Для Secrets Manager сохраняй metadata:

```bash
aws secretsmanager describe-secret \
  --secret-id "/devops/lab65/demo/app-secret" \
  --output json
```

Не сохраняй `SecretString` в proof pack.

---

## J) Упражнения

### Упражнение 1 — случайный секрет в tfvars

**Цель:** проверить, что реальные локальные input-файлы не попадут в Git.

1. В `lab_65/terraform/envs/terraform.tfvars` временно добавь учебное значение:

```hcl
lab65_fake_secret_for_ignore_test = "fake-token-do-not-use"
```

2. Проверь, что файл игнорируется:

```bash
git status --ignored
```

Ожидаемо: настоящий `terraform.tfvars` должен быть в секции ignored, а не в staged/untracked.

3. В `terraform.tfvars.example` держи только безопасную форму:

```hcl
demo_api_token_parameter_name = "/devops/lab65/demo/api-token"
demo_app_secret_name          = "/devops/lab65/demo/app-secret"
```

**Нельзя:** коммитить `terraform.tfvars`, `backend.hcl`, `tfstate`, `.terraform/`.

**Критерии**

- [ ]  реальный `terraform.tfvars` игнорируется
- [ ]  example-файл коммитится
- [ ]  временное учебное значение удалено после проверки
- [ ]  в Git не попадает ничего похожего на реальный секрет

---

### Упражнение 2 — скрытие sensitive output

**Цель:** увидеть, что `sensitive = true` скрывает вывод CLI, но не делает значение безопасным для state.

1. В `lab_65/terraform/envs` временно создай файл `scratch-sensitive-output.tf`:

```hcl
output "drill_sensitive_demo" {
  description = "Temporary drill output. Do not keep this in the lab."
  value       = sensitive("fake-sensitive-output")
  sensitive   = true
}
```

1. Запусти:

```bash
terraform fmt
terraform plan -no-color
terraform apply
terraform output -no-color
terraform output -json
```

Ожидаемо:

- обычный `terraform output` показывает `<sensitive>`
- `terraform output -json` всё ещё может содержать value
- значение попадает в state, даже если CLI его скрывает

1. Удали `scratch-sensitive-output.tf`.
2. Запусти `terraform apply`, чтобы убрать временный output из state.

**Нельзя:** использовать этот паттерн для реальных паролей/API tokens. Для реального секрета лучше чтение во время выполнения через SSM/Secrets Manager.

**Критерии**

- [ ]  ты увидел, как работает маскирование в CLI
- [ ]  ты проверил, почему `terraform output -json` и state требуют осторожности
- [ ]  временный output удалён из кода и state
- [ ]  ты можешь объяснить, почему `sensitive = true` не равно хранилище секретов

---

### Упражнение 3 — runtime-доступ к SSM

**Цель:** подтвердить, что значение секрета читает роль workload во время выполнения, а не Terraform.

1. Проверь, что SecureString существует, не выводя plaintext:

```bash
aws ssm get-parameter \
  --name "/devops/lab65/demo/api-token" \
  --with-decryption \
  --query 'Parameter.{Name:Name,Type:Type,Value:`REDACTED`}' \
  --output json
```

Если параметра ещё нет, создай demo value:

```bash
aws ssm put-parameter \
  --name "/devops/lab65/demo/api-token" \
  --type "SecureString" \
  --value "replace-me-demo-token" \
  --overwrite
```

1. Проверь Terraform policy в `lab_65/terraform/modules/network/iam.tf`: роль должна иметь `ssm:GetParameter` только на нужный parameter path.
2. Проверь приватный сетевой путь в `lab_65/terraform/modules/network/locals.tf`: должны быть endpoints `ssm`, `ssmmessages`, `ec2messages`.
3. Runtime proof с instance сохраняй только в замаскированном виде. Если проверяешь через SSM command, скрипт должен печатать `Value: "REDACTED"`, а не реальное значение.

Минимальный proof без вывода plaintext:

```bash
aws ssm get-parameter \
  --name "/devops/lab65/demo/api-token" \
  --with-decryption \
  --query 'Parameter.{Name:Name,Type:Type,Value:`REDACTED`}' \
  --output json > "$EVIDENCE_DIR/ssm-allowed-read-redacted.txt"
```

Negative test: временно проверь чтение с role/user без `ssm:GetParameter` и сохрани только `AccessDenied`, без значения секрета.

**Нельзя:** сохранять сырой вывод `aws ssm get-parameter --with-decryption` без `--query ... Value:\`REDACTED\``.

**Критерии**

- [ ]  разрешённая role может читать
- [ ]  proof содержит имя/type, но не plaintext value
- [ ]  Terraform не читает и не выводит значение секрета
- [ ]  ты можешь объяснить разницу между IAM permission и сетевым путём

---

### Упражнение 4 — только метаданные из Secrets Manager

**Цель:** разделить proof с метаданными и чтение секрета во время выполнения.

1. Создай secret, если его ещё нет:

```bash
aws secretsmanager create-secret \
  --name "/devops/lab65/demo/app-secret" \
  --secret-string '{"username":"demo","password":"replace-me"}'
```

Если secret уже существует, используй update-команду осознанно:

```bash
aws secretsmanager put-secret-value \
  --secret-id "/devops/lab65/demo/app-secret" \
  --secret-string '{"username":"demo","password":"replace-me"}'
```

2. Proof с метаданными сохраняй через `describe-secret`:

```bash
aws secretsmanager describe-secret \
  --secret-id "/devops/lab65/demo/app-secret" \
  --output json > "$EVIDENCE_DIR/secretsmanager-metadata.txt"
```

3. Runtime proof может использовать `GetSecretValue`, но вывод должен быть замаскирован. В proof pack сохраняй только:

```json
{
  "Name": "/devops/lab65/demo/app-secret",
  "Value": "REDACTED"
}
```

4. Проверь Terraform:

```bash
terraform output -no-color
terraform plan -no-color
```

Ожидаемо: Terraform показывает только name/ARN/metadata, но не `SecretString`.

**Нельзя:** сохранять `SecretString` в evidence, logs, PR comments или screenshots.

**Критерии**

- [ ]  ARN/reference виден
- [ ]  proof с метаданными не содержит `SecretString`
- [ ]  runtime proof содержит только `REDACTED`
- [ ]  ты можешь объяснить чтение секрета на runtime

---

### Упражнение 5 — проверка утечки в CI/logs

**Цель:** доказать, что secret scanner ловит утечки до merge.

1. Создай временный файл вне production-кода, например `tmp-fake-leak.txt`.
2. Добавь строку, похожую на секрет. Используй только учебный fake, не настоящий секрет:

```text
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
```

3. Запусти scanner так же, как в CI. Если workflow использует Gitleaks, локальный пример:

```bash
gitleaks detect --source . --no-git --redact
```

Если проверяешь историю Git:

```bash
gitleaks detect --source . --redact
```

1. Сохрани вывод с ошибкой в `secret-scan-fail.txt`.
2. Удали `tmp-fake-leak.txt`.
3. Повтори scan и сохрани чистый вывод в `secret-scan-clean.txt`.

**Нельзя:** коммитить учебную утечку в main. Если утечка попала в Git history, обычного удаления файла недостаточно: scanner продолжит видеть секрет в истории.

**Критерии**

- [ ]  scanner ловит учебный fake secret
- [ ]  чистое состояние восстановлено
- [ ]  ты можешь объяснить, почему leaked secret нужно rotate/revoke, даже если commit удалён

---

## Proof Pack

Для этого урока сохрани:

```text
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

Операционные доказательства можно хранить в ignored `evidence/`. Не коммить реальные значения секретов в proof pack.

---

## Частые ошибки

- считать, что `sensitive = true` не даёт значениям попасть в state
- коммитить `terraform.tfvars`
- класть секреты в user-data
- печатать секреты в GitHub Actions logs
- загружать сырые plan-артефакты, не подумав, кто имеет к ним доступ
- читать plaintext-секреты через Terraform, когда runtime access был бы безопаснее
- без явной причины публиковать `backend.hcl` с настоящими bucket/key details

---

## Security Checklist

- реальные tfvars игнорируются
- вместо настоящих inputs коммитятся examples
- outputs помечены sensitive там, где это уместно
- backend со state считается чувствительным
- в plan-артефактах нет секретов
- в CI logs нет секретов
- приложения читают секреты на runtime через IAM
- SSH/private keys не запекаются в AMI
- упражнения с fake secrets очищены после проверки

---

## Финальные критерии

Урок 65 завершён, если:

- [ ]  ты можешь объяснить разницу между `sensitive` и хранилищем секретов
- [ ]  реальные секреты не закоммичены
- [ ]  один SSM SecureString существует и читается авторизованной runtime-ролью
- [ ]  один Secrets Manager secret используется только через ARN/reference
- [ ]  CI/logs/artifacts не раскрывают значения секретов
- [ ]  practical walkthrough выполнен с redacted proof pack
- [ ]  минимум 3 упражнения на утечки выполнены и очищены после проверки

---

## Итоги Урока

- **Что изучил:** безопасность чувствительных данных в Terraform, state, CI и runtime.
- **Что практиковал:** безопасные inputs, ignored tfvars, sensitive outputs, SSM SecureString, метаданные Secrets Manager, secret scanning.
- **Операционный фокус:** Terraform должен управлять доступом и ссылками, а не протаскивать plaintext-секреты через pipeline.
- **Почему это важно:** даже идеальный deployment pipeline небезопасен, если он раскрывает credentials.

Главная модель урока:

```text
Git не должен хранить значения.
Terraform не должен читать значения.
CI не должен печатать значения.
AWS хранит значения.
Workload читает значения на runtime через IAM.
```

Для runtime-доступа нужны три условия:

```text
Runtime secret access = IAM permission + network path to AWS API + redacted logging.
```

Если есть IAM permission, но нет сетевого пути, приватный workload не дойдёт до AWS API и получит timeout/hang.

Если сетевой путь есть, но нет IAM permission, AWS вернёт `AccessDenied`.

На примере `terraform-plan-pr.yml` это выглядит так:

- в Git хранится логика workflow и безопасные defaults
- GitHub variables могут хранить non-secret config вроде role ARN, bucket name и region
- AWS SSM Parameter Store может хранить shared/internal config
- AWS SSM SecureString или Secrets Manager хранят настоящие secret values
- logs, artifacts и PR comments должны содержать только metadata или `REDACTED`
