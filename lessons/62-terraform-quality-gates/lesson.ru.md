# lesson_62

---

# Terraform Quality Gates & Policy Baseline (`fmt`, `validate`, `tflint`, `checkov`)

**Date:** 2026-03-24

**Focus:** после lesson 60-61 уже есть remote state и safe refactors. Теперь нужно следующее: автоматические quality gates, которые блокируют footguns ещё до apply.

**Mindset:** хороший Terraform workflow должен ломаться рано. Не на `apply`, не после инцидента, а на `fmt`, `validate`, `tflint`, `checkov` и CI gate.

---

## Зачем Этот Урок

После lesson 61 ты уже умеешь безопасно работать со state.
Даже при чистом state и хорошем refactor можно закоммитить плохой код:

- открыть лишний ingress
- убрать IMDSv2
- сломать backend protection
- забыть tags
- протащить insecure defaults в PR

Этот урок не про тяжёлый enterprise policy-as-code, а про минимальный, но реальный baseline качества:

- форматирование
- синтаксис и валидация
- линтинг Terraform/AWS
- security/misconfig scanning
- CI, который режет плохие изменения

---

## Что Должно Получиться

- понимать разницу между `fmt`, `validate`, `tflint`, `checkov`
- запускать локальные quality gates до коммита
- собрать CI gate для Terraform paths
- иметь хотя бы 3 воспроизводимых footgun-drill сценария
- доказать, что плохой код блокируется до `apply`

---

## Quick Path

1. Поднять локальный baseline: `terraform fmt -check`, `terraform validate`.
2. Добавить `tflint` config для `lab_62/terraform`.
3. Добавить `checkov` config для Terraform scan.
4. Подготовить example CI workflow.
5. Сделать 3 deliberate bad changes.
6. Доказать, что quality gates их ловят.
7. Сохранить proof artifacts.

---

## Prerequisites

- lesson 60 completed
- lesson 61 completed
- `lab_62/terraform/envs` уже существует и инициализируется
- AWS CLI + Terraform configured
- готовность запускать локальные проверки много раз

---

## Структура Урока

```text
lessons/62-terraform-quality-gates/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── checkov.yaml
├── ci/
│   └── terraform-quality-gates.yml
└── lab_62/
    ├── packer/
    └── terraform/
        ├── .tflint.hcl
        ├── backend-bootstrap/
        ├── envs/
        └── modules/network/
```

---

## Что Ловит Каждый Инструмент

### `terraform fmt -check`

Ловит:

- неотформатированный HCL
- лишний шум в diff

Не ловит:

- логические ошибки
- security issues

### `terraform validate`

Ловит:

- синтаксические ошибки
- invalid references
- часть schema ошибок

Не ловит:

- insecure patterns
- слабые архитектурные решения

### `tflint`

Ловит:

- AWS/Terraform lint-проблемы
- часть плохих аргументов и устаревших настроек
- custom policy baseline, если настроить rules

### `checkov`

Ловит:

- misconfig/security issues
- IMDSv2 disabled
- risky SG patterns
- storage hardening gaps

Практическое правило:

- `fmt` и `validate` это hygiene baseline
- `tflint` это Terraform/AWS lint layer
- `checkov` это security/misconfig layer

---

## Local Quality Gate Baseline

Рабочая директория:

```bash
cd lessons/62-terraform-quality-gates/lab_62/terraform
```

Базовый прогон:

```bash
terraform fmt -recursive
terraform fmt -check -recursive
terraform -chdir=envs init -backend=false
terraform -chdir=envs validate

tflint --chdir=envs --init
tflint --chdir=envs -f compact

checkov -d . --framework terraform --config-file ../../checkov.yaml
```

---

## TFLint Baseline

Используй `lab_62/terraform/.tflint.hcl`.

Он должен закрывать минимум:

- AWS ruleset
- Terraform recommended preset
- понятный compact output

Это хороший early-warning слой.

---

## Checkov Baseline

Используй `checkov.yaml` в корне lesson 62.

Идея здесь такая:

- не пытаться покрыть вообще всё на свете
- сфокусироваться на реально важных misconfig-паттернах для этой лабы
- использовать soft-fail только там, где ты осознанно не хочешь падать

В этой lesson-линии нас особенно интересуют:

- EC2 metadata hardening
- security groups
- backend bucket protections

Именно поэтому `checkov.yaml` в этом уроке должен быть **curated**, а не “проверить вообще всё сразу”.

---

## CI Shape

В репо уже есть старый `terraform-ci` workflow для другого path.

Для lesson 62 его не нужно ломать или переписывать
Лучше рядом с уроком держать пример:

- `ci/terraform-quality-gates.yml`

А потом уже осознанно переносить его в `.github/workflows/`.

Так ты не смешиваешь обучение с поломкой существующего CI.

Быстрая локальная проверка YAML

```hcl
python3 - <<'PY'
import yaml, pathlib
p = pathlib.Path("lessons/62-terraform-quality-gates/ci/terraform-quality-gates.yml")
print(yaml.safe_load(p.read_text())["name"])
PY
```

---

## Footgun Drills (Обязательные)

### Drill 1: Public ingress footgun

Сделай deliberate bad change:

- добавь ingress `0.0.0.0/0` на `22`, `80` или `443` туда, где этого не должно быть

Ожидаемый результат:

- `checkov` и/или другой gate должен упасть

### Drill 2: IMDSv2 removed

Убери:

```hcl
metadata_options {
  http_tokens = "required"
}
```

из `aws_launch_template.web` или `aws_instance.ssm_proxy`.

Ожидаемый результат:

- `checkov` должен упасть на missing IMDSv2 requirement

### Drill 3: Backend bucket protection broken

```hcl
terraform -chdir=backend-bootstrap init -backend=false
terraform -chdir=backend-bootstrap validate
tflint --chdir=backend-bootstrap -f compact
checkov -d backend-bootstrap --framework terraform --config-file ../../checkov.yaml
```

Во `backend-bootstrap/main.tf` временно испорть один из protection layers:

- versioning
- encryption
- public access block

Ожидаемый результат:

- `checkov` должен зафиксировать misconfig

### Drill 4: Tags/consistency drift

Сделай изменение, которое нарушает твой naming/tag baseline.

Ожидаемый результат:

- `tflint` и/или code review baseline должны показать, что naming/policy discipline разъехалась

---

## Как Проводить Drill Правильно

Для каждого drill:

1. Сначала сохрани baseline output.
2. Потом внеси один плохой change.
3. Снова запусти gate.
4. Сохрани failing output.
5. Верни good state.
6. Запусти gate ещё раз и сохрани clean output.

То есть не просто “сломал и починил”, а:

- baseline
- fail
- fix
- clean

---

## Common Pitfalls

- не пытайся сразу строить OPA/Sentinel policy platform
- не тащи весь repo в один giant checkov scan без scope
- не полагайся только на CI, если локально можно поймать ошибку за 10 секунд
- не делай allowlist без объяснения, почему исключение допустимо

---

## Что Мы Специально Не Чиним В Этом Уроке

В lesson 62 мы сознательно **не закрываем весь дефолтный Checkov output**.

Оставляем вне scope:

- ALB access logging
- ALB HTTPS/TLS-only listener model
- Target group HTTP -> HTTPS redesign
- S3 KMS-by-default вместо AES256
- S3 replication
- S3 access logging
- S3 lifecycle/event notifications
- VPC flow logs
- полную перестройку SG egress-модели

Почему:

- это уже не “quality gates baseline”
- это тянет за собой новые ресурсы, bucket-и, policy-и, cert-и, logging stack

Внутри этой lesson-линии мы фиксируем только дешёвые и понятные вещи:

- IMDSv2 hardening
- EC2 monitoring / root volume encryption для proxy instance
- ALB deletion protection и invalid header handling
- default security group lockdown
- curated Checkov scope под реальные цели урока

---

## Proof Pack (Обязательные Артефакты)

Минимум:

- baseline run output
- failing output для каждого drill
- fixed output после возврата
- короткий notes/decision файл:
  - что сломал
  - какой инструмент поймал
  - почему это важно

Готовый шаблон в `proof-pack.ru.md`.

---

## Final Acceptance

Lesson 62 закрыт, если:

- [ ] ты можешь объяснить разницу между `fmt`, `validate`, `tflint`, `checkov`
- [ ] локальный baseline gate работает
- [ ] у тебя есть пример CI workflow для Terraform quality gates
- [ ] минимум 3 footgun drills реально пойманы quality gates
- [ ] по каждому drill есть proof artifacts

---

## Lesson Summary

- **Что изучил:** как строить Terraform quality gates до `apply`.
- **Что практиковал:** `terraform fmt`, `terraform validate`, `tflint`, `checkov`, deliberate bad changes и их блокировку.
- **Операционный фокус:** ломать рано, а не поздно; ловить плохой код до `plan/apply`.
- **Почему это важно:** remote state и safe refactors не спасают, если плохой код попадает в repo.
