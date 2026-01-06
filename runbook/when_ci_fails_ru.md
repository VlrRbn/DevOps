# Mini runbook: when CI fails (Terraform CI)

## 0. Быстрый триаж

| Симптом в Actions                         | Где упало   | Что это обычно значит                           |
| ----------------------------------------- | ----------- | ----------------------------------------------- |
| `Terraform fmt (check)` failed            | fmt         | форматирование                                  |
| `Terraform init` failed                   | init        | провайдер/версии/зеркала/бэкенд/сеть            |
| `Terraform validate` failed               | validate    | синтаксис/типы/модульные входы                  |
| `TFLint init` failed                      | tflint init | плагины не скачались/нет конфига/доступ         |
| `TFLint` failed                           | tflint      | линт-ошибки (AWS/terraform best practices)      |
| `Configure AWS credentials (OIDC)` failed | OIDC        | trust policy/permissions/id-token               |
| `Terraform plan` failed                   | plan        | нет прав/нет vars/локальный file()/data sources |

---

## 1 fmt failed

### Симптом

`terraform fmt -check -diff -recursive` вернул ошибку.

### Фикс локально

```bash
cd labs/lesson_40/terraform
terraform fmt -recursive
git add -A
git commit -m "style(terraform): fmt"
git push
```

---

## 2 init failed

### Частые причины

* провайдер не скачивается (сеть)
* версия Terraform/провайдера конфликтует
* случайно подключён remote backend

### Фикс локально

```bash
cd labs/lesson_40/terraform
rm -rf .terraform .terraform.lock.hcl
terraform init -backend=false
```

### В CI

Убедись, что стоит:

```bash
terraform init -backend=false -input=false -no-color
```

---

## 3 validate failed

### Симптом

Ошибки типа: `Unexpected block`, `Invalid value`, `Missing required argument`.

### Фикс локально

```bash
cd labs/lesson_40/terraform
terraform init -backend=false
terraform validate
```

### Частые причины

* сломал синтаксис HCL
* не совпали типы переменных
* модуль ожидает переменную, а ты не передал

---

## 4 tflint init failed

### Симптом

`tflint --init` не скачал ruleset / плагины.

### Фикс локально

```bash
cd labs/lesson_40/terraform
tflint --init
```

### Проверь

* файл `.tflint.hcl` лежит в `labs/lesson_40/terraform/.tflint.hcl`
* в workflow правильно задан `tflint_config_path`

---

## 5 tflint failed

### Симптом

Ошибки типа: “invalid argument”, “deprecated”, “unused”, “aws_* rule violated”.

### Фикс локально

```bash
cd labs/lesson_40/terraform
tflint --init
tflint -f compact
```

### Подход

* сначала чинить **ошибки**, потом “warnings”
* если правило реально мешает — можно точечно отключить, но лучше понять почему оно ругается

---

## 6 Configure AWS credentials (OIDC) failed

### Симптомы

* `Not authorized to perform sts:AssumeRoleWithWebIdentity`
* `No OIDC token available`
* `AccessDenied`

### Проверки

1. В workflow есть:

```yaml
permissions:
  id-token: write
```

2. Trust policy роли разрешает твой `sub`:

* `repo:VlrRbn/DevOps:ref:refs/heads/main`
* `repo:VlrRbn/DevOps:pull_request` (если план на PR)

---

## 7 plan failed

### 7a Нет файла/локальные пути (`file("~/.ssh/...")`)

**Симптом:** `no file exists at /home/runner/...`
**Фикс:** не читать файлы из `~` в CI.

* передавать значение через переменную (`public_key`)
* или хранить файл в репе и читать через `${path.module}` / `${path.root}`

### 7b Не хватает AWS прав

**Симптом:** `AccessDenied` на `ec2:Describe*`, `iam:*`, `kms:*`…
**Фикс:** расширь permissions роли минимум до read-only нужных сервисов.

### 7c provider требует profile

**Симптом:** `failed to get shared config profile`
**Фикс:** убери `profile =` из `provider "aws" {}` — в CI креды приходят через OIDC.

### 7d vars отсутствуют

**Симптом:** `No value for required variable`
**Фикс:** добавь в `envs/dev.tfvars` или передай `-var`/`TF_VAR_*`.

---

## 8 “CI зелёный, но ничего не проверяет”

### Симптом

Workflow проходит за секунду, но должен был падать.

### Причина

`paths:` фильтр не совпал с тем, что менял.

### Проверка

Измени файл внутри:

* `labs/lesson_40/terraform/**`
  или сам workflow:
* `.github/workflows/terraform-ci.yml`

---

## Полезные локальные команды (чтобы повторить CI 1:1)

```bash
cd labs/lesson_40/terraform
terraform fmt -check -diff -recursive
terraform init -backend=false -input=false
terraform validate
tflint --init
tflint -f compact
terraform plan -input=false -no-color -var-file=envs/dev.tfvars
```
