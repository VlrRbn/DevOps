# Урок 70. Policy as Code на Terraform JSON Plan

**Дата:** 2026-06-05

**Фокус:** проверять сохранённый Terraform plan как структурированные данные и блокировать рискованные изменения до apply.

**Главная идея:** человек смотрит контекст, а policy ловит повторяемые ошибки. Если правило объективное, оно должно быть в коде.

---

## Зачем нужен этот урок

В уроке 68 сделали контролируемый apply pipeline.

В уроке 69 разделили GitHub Actions роли на plan/apply и ограничили IAM.

В уроке 70 добавляем следующий защитный слой: policy поверх `tfplan.json`.

Pipeline уже умеет создавать сохранённый plan:

```bash
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
```

Теперь plan должен пройти policy до того, как подтверждённая apply job сможет его применить.

Работаем с `jq`, потому что это прозрачно, легко отлаживать и удобно читать в CI logs. OPA/Rego остаётся следующим уровнем, когда shell-policy становится слишком большой.

Ссылки:

- Terraform JSON plan format: https://developer.hashicorp.com/terraform/internals/json-format
- `terraform show -json`: https://developer.hashicorp.com/terraform/cli/commands/show
- OPA Terraform guide: https://www.openpolicyagent.org/docs/terraform
- Rego policy language: https://www.openpolicyagent.org/docs/policy-language
- Conftest: https://www.conftest.dev/

---

## Что должно получиться

После урока должен уметь:

- генерировать `tfplan.json` из сохранённого Terraform plan
- читать `.resource_changes[]` и `.change.actions`
- надёжно находить delete и replacement
- блокировать public ingress в отдельных правилах и inline-блоках security group
- требовать непустые обязательные governance-теги на ресурсах с тегами
- разделять жёсткий запрет и предупреждение
- разрешать destroy только через точный Terraform address
- сохранять policy evidence рядом с plan artifact
- понимать, где заканчивается jq-policy и когда нужен OPA/Rego

---

## Структура репозитория

```text
lessons/70-policy-as-code-terraform-json-plan/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── lesson70-terraform-apply-dev.yml
├── policies/
│   ├── terraform-plan-policy.sh
│   ├── test-policy.sh
│   ├── test-opa.sh
│   ├── allow-destroy.example.json
│   ├── opa/
│   │   └── terraform.rego
│   └── tests/
│       ├── safe-plan.json
│       ├── destroy-plan.json
│       ├── replacement-plan.json
│       ├── public-ingress-plan.json
│       ├── public-ingress-inline-sg-plan.json
│       ├── public-egress-plan.json
│       ├── missing-tags-plan.json
│       ├── empty-tags-plan.json
│       ├── warn-plan.json
│       ├── no-op-warn-plan.json
│       ├── allow-destroy-wrong-address.json
│       ├── allow-destroy-invalid-wildcard.json
│       └── allow-destroy-expired.json
└── lab_70/
    ├── packer/
    └── terraform/
```

---

## A) Модель Terraform JSON Plan

Самое важное поле:

```jq
.resource_changes[]
```

Один resource change содержит Terraform address, тип ресурса и список actions:

```json
{
  "address": "module.network.aws_lb.app",
  "mode": "managed",
  "type": "aws_lb",
  "change": {
    "actions": ["update"],
    "before": {},
    "after": {}
  }
}
```

Типовые actions:

| Actions | Значение | Что делает policy |
| --- | --- | --- |
| `["no-op"]` | нет изменений | игнорирует |
| `["create"]` | новый ресурс | проверяет атрибуты |
| `["update"]` | update in-place | проверяет рискованные атрибуты при необходимости |
| `["delete"]` | destroy | deny по умолчанию |
| `["delete", "create"]` | replacement | deny по умолчанию |
| `["create", "delete"]` | create-before-destroy replacement | deny по умолчанию |

Главное правило:

```text
if actions contains "delete" => destructive change
```

Почему так?

Потому что `replacement` тоже содержит `delete`:

```text
"actions": ["delete", "create"]
```

Значит policy не должна проверять только точное равенство:

```text
actions == ["delete"]
```

Она должна проверять:

```text
actions contains "delete"
```

Так мы ловим и прямой destroy, и replacement.

---

## B) Уровни policy

Не каждая находка должна блокировать apply.

Используем три уровня:

| Уровень | Значение | Примеры |
| --- | --- | --- |
| `deny` | блокирует apply | destroy, public ingress, отсутствующие или пустые required tags |
| `warn` | разрешает, но фиксирует | новый или изменяемый NAT gateway, ASG max size, public ALB |
| `info` | только evidence | количество изменённых ресурсов, timestamp |

В уроке 70 реализовано:

**Deny:**

- destructive changes без точного exception
- public ingress из `0.0.0.0/0` или `::/0`
- отсутствующие или пустые required tags: `Project`, `Environment`, `ManagedBy`

Public ingress проверяется в двух моделях Terraform:

- отдельные rule resources: `aws_security_group_rule` с `type = "ingress"` и `aws_vpc_security_group_ingress_rule`
- inline `ingress` внутри `aws_security_group`

Исходящее egress-правило на `0.0.0.0/0` этим правилом не блокируется. Это отдельная политика, а не public ingress.

**Warn:**

- новый или изменяемый NAT Gateway
- новый или изменяемый ASG с `max_size > 4`
- новый или изменяемый public ALB

Warning rules специально игнорируют `no-op` resources, чтобы уже принятый старый риск не создавал шум в release checks.

Разница:

```text
deny  -> workflow падает, apply нельзя делать
warn  -> workflow не падает, но человек должен увидеть предупреждение
```

---

## C) Локальные policy tests

Из корня репозитория:

```bash
lessons/70-policy-as-code-terraform-json-plan/policies/test-policy.sh
# Optional, если установлен opa:
lessons/70-policy-as-code-terraform-json-plan/policies/test-opa.sh
```

Обязательный ожидаемый output:

```text
policy tests passed
```

Optional OPA output, если `opa` установлен:

```text
opa policy tests passed
```

Тестовый скрипт проверяет набор тестовых планов:

| Fixture | Ожидаемый результат |
| --- | --- |
| `safe-plan.json` | allow |
| `warn-plan.json` | allow с предупреждениями |
| `no-op-warn-plan.json` | allow без предупреждений |
| `destroy-plan.json` | deny |
| `replacement-plan.json` | deny |
| `public-ingress-plan.json` | deny |
| `public-ingress-inline-sg-plan.json` | deny |
| `public-egress-plan.json` | allow |
| `missing-tags-plan.json` | deny |
| `empty-tags-plan.json` | deny |
| неправильный destroy exception | deny |
| wildcard destroy exception | ошибка входных данных |
| истёкший destroy exception | ошибка входных данных |

Это быстрый способ проверить policy без AWS-ресурсов.

Главный flow скрипта:

```text
1. проверить, что jq установлен
2. проверить, что tfplan.json существует
3. если есть ALLOW_DESTROY_FILE, проверить формат и срок действия
4. найти destructive changes
5. применить destroy exceptions, если они есть
6. найти public ingress
7. найти отсутствующие или пустые теги
8. найти предупреждения
9. собрать список запретов
10. собрать список предупреждений
11. принять решение ALLOW или DENY
```

Древо решения:

```text
Read tfplan.json
│
├─ Validate jq exists
├─ Validate plan file exists
├─ Проверить optional allow-destroy file
│   └─ Отклонить сломанные, истёкшие, пустые или wildcard exceptions
│
├─ Найти destructive changes
│   └─ Убрать явно разрешённые destructive addresses
│
├─ Найти public ingress в отдельных SG rules
│   └─ aws_security_group_rule проверяется только когда type == "ingress"
├─ Найти public ingress в inline aws_security_group ingress
├─ Найти ресурсы без required tags или с пустыми значениями тегов
│
├─ Find warning signals только для create/update actions:
│   ├─ NAT Gateway
│   ├─ ASG max_size > 4
│   └─ public Load Balancer
│
├─ Merge deny findings
├─ Merge warning findings
│
├─ If deny_count > 0:
│   └─ DENY, exit 2
│
└─ Else:
    └─ ALLOW, print warnings if any, exit 0
```

---

## D) Реальный Terraform JSON Plan

Когда нужно проверить настоящий Terraform output, используй lab.

Из директории env:

```bash
cd lessons/70-policy-as-code-terraform-json-plan/lab_70/terraform/envs
terraform init -reconfigure -backend-config=backend.hcl
terraform plan -out=tfplan
terraform show -no-color tfplan > tfplan.txt
terraform show -json tfplan > tfplan.json
```

Запуск policy:

```bash
OUT_DIR=policy-results ../../../policies/terraform-plan-policy.sh tfplan.json
```

Ожидаемый короткий вывод в консоль:

```text
POLICY_DECISION=ALLOW
deny_count=0
warn_count=0
policy_results_dir=policy-results
```

Если есть `deny`, скрипт печатает такой же summary и JSON со списком найденных нарушений. Детали всегда сохраняются в `policy-results/`.

Проверить решение:

```bash
cat policy-results/policy-decision.txt
jq . policy-results/policy-deny.json
jq . policy-results/policy-warn.json
```

Коды выхода:

| Код выхода | Значение |
| --- | --- |
| `0` | policy разрешила plan |
| `1` | ошибка скрипта или входных данных |
| `2` | policy заблокировала plan |

Разница между `1` и `2` полезна:

```text
1 = мы неправильно запустили проверку
2 = проверка запустилась правильно и нашла запрещённое изменение
```

---

## E) Destructive Exceptions

Destroy/replacement запрещён по умолчанию.

Пример destructive rule

В скрипте логика такая:

```json
.resource_changes[]?
| select(.mode == "managed")
| select(.change.actions | index("delete"))
```

Ключевая часть - `index("delete")` и она ловит все destructive варианты.

Результат попадает в `destructive.json`

```text
.resource_changes[]?
| select(.mode == "managed")
| select(.change.actions | index("delete"))
```

Если destructive change действительно нужен, используется exception file с точными Terraform addresses:

```json
{
  "reason": "retire obsolete alarm after incident review",
  "approved_by": "CHANGE-1234",
  "expires": "2099-12-31",
  "allowed_addresses": [
    "module.network.aws_cloudwatch_metric_alarm.old_alarm"
  ]
}
```

Запуск:

```bash
ALLOW_DESTROY_FILE=../../../policies/allow-destroy.example.json \
OUT_DIR=policy-results \
../../../policies/terraform-plan-policy.sh tfplan.json
```

Правила для exceptions:

- точные addresses, не wildcards
- ссылка на approval обязательна
- дата истечения обязательна
- exception file сохраняется в proof pack
- после изменения exception удаляется

Скрипт валидирует exception metadata до применения exception. Отсутствующий файл, пустая metadata, неправильная дата истечения, пустой список addresses или wildcard address — это ошибка входных данных, а не разрешение от policy.

Exception file не заменяет review. Он делает риск явным и проверяемым.

---

## F) Интеграция в CI

Правильный порядок:

1. checkout
2. `fmt`/test/validate
3. принять plan role
4. создать `tfplan`
5. создать `tfplan.json`
6. запустить policy
7. загрузить plan и policy artifacts
8. подтвердить GitHub Environment
9. принять apply role
10. применить точный сохранённый `tfplan`
11. выполнить post-apply drift check

Ключевой момент: approval делается после того, как plan и policy artifacts уже существуют.

Файл урока:

```text
lessons/70-policy-as-code-terraform-json-plan/ci/lesson70-terraform-apply-dev.yml
```

Policy step внутри plan job:

```bash
mkdir -p policy-results
OUT_DIR=policy-results ../../../policies/terraform-plan-policy.sh tfplan.json 2>&1 | tee policy-results/policy-output.txt
```

Apply job должен применять ровно тот binary `tfplan`, который был загружен как подтверждённый artifact. Нельзя после approval запускать новый plan и считать его подтверждённым.

---

## G) Что эта policy не решает

Policy на `tfplan.json` не заменяет:

- least-privilege IAM
- GitHub Environment approval
- drift detection
- post-apply checks
- human review `tfplan.txt`
- service-specific release gates

Это механический защитный барьер между plan и apply.

---

## H) Опциональный путь OPA/Rego

Основная реализация урока — jq-policy.

OPA/Rego имеет смысл, когда:

- правил становится слишком много для shell
- несколько repositories должны использовать одну policy library
- нужны полноценные unit tests для policy rules
- security/platform команда владеет policy отдельно от application code

Дополнительный пример:

```text
lessons/70-policy-as-code-terraform-json-plan/policies/opa/terraform.rego
```

Пример написан в современном Rego v1 стиле: `deny contains msg if { ... }`. Старый стиль `deny[msg] { ... }` в новых версиях OPA может ломаться или требовать compatibility mode. Запускать `policies/test-opa.sh`, чтобы проверить optional Rego на fixtures урока.

Если установлен `conftest`:

```bash
conftest test tfplan.json --policy ../../../policies/opa --namespace terraform.plan
```

Добавлять OPA только когда набор policy rules стал достаточно большим.

---

## I) Упражнения

### Упражнение 1. Безопасный plan разрешается

```bash
OUT_DIR=/tmp/l70-safe lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/safe-plan.json
cat /tmp/l70-safe/policy-decision.txt
```

Ожидаемо:

```text
POLICY_DECISION=ALLOW
```

### Упражнение 2. Destroy блокируется

```bash
set +e
OUT_DIR=/tmp/l70-destroy lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/destroy-plan.json
echo $?
set -e
jq . /tmp/l70-destroy/policy-deny.json
```

Ожидаемый код выхода: `2`.

### Упражнение 3. Public ingress блокируется

```bash
set +e
OUT_DIR=/tmp/l70-public lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/public-ingress-plan.json
echo $?
set -e
jq . /tmp/l70-public/policy-deny.json
```

Ожидаемое rule: `deny_public_ingress`.

Дополнительная проверка: public egress не должен блокироваться правилом ingress.

```bash
OUT_DIR=/tmp/l70-egress lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/public-egress-plan.json
cat /tmp/l70-egress/policy-decision.txt
```

Ожидаемо: `POLICY_DECISION=ALLOW`.

### Упражнение 4. Отсутствующие или пустые tags блокируются

```bash
set +e
OUT_DIR=/tmp/l70-tags lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/missing-tags-plan.json
echo $?
set -e
jq . /tmp/l70-tags/policy-deny.json
```

Ожидаемое rule: `deny_missing_required_tags`.

Дополнительная проверка: ключ тега есть, но значение пустое.

```bash
set +e
OUT_DIR=/tmp/l70-empty-tags lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/empty-tags-plan.json
echo $?
set -e
jq . /tmp/l70-empty-tags/policy-deny.json
```

Ожидаемое rule: `deny_missing_required_tags`.

### Упражнение 5. Warning не блокирует

```bash
OUT_DIR=/tmp/l70-warn lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/warn-plan.json
cat /tmp/l70-warn/policy-decision.txt
jq . /tmp/l70-warn/policy-warn.json
```

Ожидаемо:

- код выхода `0`
- `POLICY_DECISION=ALLOW`
- warning существует

### Упражнение 6. Точный destroy exception

```bash
ALLOW_DESTROY_FILE=lessons/70-policy-as-code-terraform-json-plan/policies/allow-destroy.example.json \
OUT_DIR=/tmp/l70-destroy-allowed \
lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/destroy-plan.json
cat /tmp/l70-destroy-allowed/policy-decision.txt
jq . /tmp/l70-destroy-allowed/policy-deny.json
```

Ожидаемо:

- `POLICY_DECISION=ALLOW`
- пустой deny array

### Упражнение 7. Wildcard destroy exception отклоняется

```bash
set +e
ALLOW_DESTROY_FILE=lessons/70-policy-as-code-terraform-json-plan/policies/tests/allow-destroy-invalid-wildcard.json \
OUT_DIR=/tmp/l70-invalid-exception \
lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/destroy-plan.json
echo $?
set -e
```

Ожидаемо:

- код выхода `1`
- policy не разрешает plan
- ошибка объясняет, что wildcard addresses невалидны

### Упражнение 8. Истёкший destroy exception отклоняется

```bash
set +e
ALLOW_DESTROY_FILE=lessons/70-policy-as-code-terraform-json-plan/policies/tests/allow-destroy-expired.json \
OUT_DIR=/tmp/l70-expired-exception \
lessons/70-policy-as-code-terraform-json-plan/policies/terraform-plan-policy.sh \
  lessons/70-policy-as-code-terraform-json-plan/policies/tests/destroy-plan.json
echo $?
set -e
```

Ожидаемо:

- код выхода `1`
- policy не разрешает plan
- ошибка объясняет, что exception истёк

---

## Пакет доказательств

Сохраняй evidence в игнорируемой папке, например:

```text
lessons/70-policy-as-code-terraform-json-plan/evidence/l70-YYYYmmdd_HHMMSS/
```

Минимум:

- `tfplan.txt`
- `tfplan.json`
- `policy-decision.txt`
- `policy-output.txt`
- `policy-deny.json`
- `policy-warn.json`
- `destructive.json`
- `missing-tags.json`
- `public-ingress-rules.json`
- URL plan job или скриншот
- apply approval result, если запускался CI

Используй `proof-pack.ru.md` как чеклист.

---

## Частые ошибки

- Запускать policy по текстовому plan вместо JSON.
- Искать `destroy` через grep в `tfplan.txt` и пропускать replacement.
- Считать пустое значение required tag валидным тегом.
- Блокировать public egress правилом для public ingress.
- Делать approval до того, как появился финальный `tfplan`.
- В apply job запускать новый plan вместо подтверждённого binary plan.
- Не смотреть warnings, потому что они не блокируют.
- Разрешать destroy через wildcard вместо точного Terraform address.
- Не проверять срок действия destroy exception относительно текущей UTC-даты.
- Считать invalid exception file approval-ом вместо того, чтобы падать на ошибке входных данных.
- Забывать, что `terraform show -json tfplan` может содержать чувствительные значения в зависимости от ресурсов и поведения provider.

---

## Финальные критерии

Урок закрыт, когда:

- [ ] локальные policy tests проходят
- [ ] настоящий или fixture plan создаёт `policy-decision.txt`
- [ ] правила deny блокируют ожидаемые плохие plans
- [ ] warnings видны, но не блокируют
- [ ] CI template загружает policy artifacts вместе с plan
- [ ] можешь объяснить, почему policy запускается до environment approval/apply

---

## Итоги урока

- **Что изучил:** Terraform plan можно проверять как структурированные данные, а не только читать глазами.
- **Что практиковал:** генерацию JSON plan, проверки через jq, решения deny/warn, exact destroy exceptions.
- **Операционный навык:** превращать повторяемые review rules в автоматические проверки перед apply.
- **CI фокус:** сначала plan, потом policy, затем approval, после этого apply точного подтверждённого артефакта.
