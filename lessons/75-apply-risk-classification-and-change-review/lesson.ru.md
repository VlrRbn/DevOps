# Apply Risk Classification & Change Review

**Дата:** 2026-06-26

**Фокус:** объединить данные Terraform plan, результаты policy, cost warnings, целевое окружение, promotion evidence и контекст инцидента в финальное решение о риске apply.

**Подход:** разрешённый plan не означает низкий риск. Approval должен соответствовать уровню риска.

---

## 1. Зачем нужен этот урок

К этому моменту цепочка доставки уже содержит отдельные проверки:

```text
native tests -> security policy -> cost policy -> promotion evidence -> controlled apply -> least-privilege IAM -> recovery runbooks
```

Но все эти проверки отвечают на разные вопросы.

`security policy` отвечает:

```text
Это изменение вообще разрешено?
```

Например:

- нет `public ingress`;
- нет `destroy` без exception;
- есть required tags.

`cost policy` отвечает:

```text
Это изменение не выходит за cost/blast-radius рамки?
```

Например:

- ASG не слишком большой;
- NAT в `dev` запрещён;
- public ALB даёт warning.

`promotion evidence` отвечает:

```text
Это изменение реально прошло предыдущую среду?
```

Например:

- `stage apply` должен доказывать, что `dev` был проверен;
- `prod apply` должен доказывать, что `stage` был проверен.

Но остаётся главный вопрос перед approval:

```text
Какой уровень риска у apply?
```

Потому что `allowed` не равно `low risk`.

Примеры:

| Plan | Результат policy | Реальный риск на ревью |
| --- | --- | --- |
| Обновление одного tag в `dev` | allow | low |
| Добавление NAT Gateway в `stage` | allow with warning | medium |
| Обновление ASG launch template в `prod` | может быть разрешено policy | high |
| Удаление старого alarm с approved exception | allow with exception | medium/high |
| Apply во время активного инцидента | технически возможно | emergency |
| Public ingress | deny | blocked |

Урок 75 добавляет финальный слой:

```text
policy/cost/promote/context -> risk-decision.json / risk-decision.md
```

Артефакт показывает, что изменилось, какое окружение затрагивается, какие policy сработали как `warn`/`deny`, есть ли promotion evidence, какой уровень approval нужен и можно ли запускать `apply`.

**Главная модель**
```text
Policy решает: можно или нельзя.
Risk classification решает: насколько строго это нужно проверять.
```

**Почему это важно**
Если у тебя есть только `allow/deny`, то все разрешённые изменения выглядят одинаково.

Это плохо, потому что:

```text
tag в dev
```

и

```text
IAM/ASG change в prod
```

могут оба быть `allowed`, но уровень review должен быть разный.

`risk-decision.json` нужен машине/CI:

```json
{
  "risk": "HIGH",
  "apply_allowed": true,
  "approval_required": true,
  "approval_level": "senior_reviewer_or_prod_environment",
  "reason_codes": ["target_env_prod"]
}
```

`risk-decision.md` нужен человеку:

```text
Risk: HIGH
Apply allowed: true
Approval required: true
Reason Codes:
- target_env_prod
```

**Сразу важное различие**
`apply_allowed=true` не значит “можно сразу применять”.

Это значит:

```text
risk gate не заблокировал apply
```

Но если:

```text
approval_required=true
```

то человек или GitHub Environment всё равно должен дать approval.

---

## 2. Результаты урока

После урока ты должен уметь:

- классифицировать apply как `NO_CHANGE`, `LOW`, `MEDIUM`, `HIGH`, `EMERGENCY` или `BLOCKED`;
- объединять outputs из security policy и cost policy;
- использовать окружение как множитель риска;
- требовать promotion evidence для `stage`/`prod`;
- считать IAM, destroy, replacement и изменения в `prod` более высоким риском;
- генерировать risk artifacts для машинной обработки и ревью;
- объяснить, почему “policy allowed” не всегда означает “low risk”.

---

## 3. Связь с предыдущими уроками

| Урок | Что уже есть | Что добавляет урок 75 |
| --- | --- | --- |
| 68 | controlled apply | финальное risk decision до approval/apply |
| 70 | JSON plan policy | security deny/warn как входные данные |
| 71 | promotion chain | promotion evidence как входные данные для risk |
| 73 | cost/blast-radius policy | cost deny/warn как входные данные |
| 74 | recovery runbooks | emergency classification и break-glass context |

Главная модель:

```text
Policy decides whether a plan is allowed.
Risk classification decides how much review it needs.
```

---

## 4. Структура репозитория

```text
lessons/75-apply-risk-classification-and-change-review/
├── README.md
├── lesson.en.md
├── lesson.ru.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   ├── lesson75-risk-review.yml
│   └── lesson75-real-plan-risk-review.yml
├── scripts/
│   ├── run-local-checks.sh
│   ├── promotion-evidence-template.sh
│   └── reviewer-note-template.sh
├── policies/
│   ├── terraform-plan-policy.sh
│   ├── cost-policy.sh
│   ├── risk-classifier.sh
│   ├── test-risk-classifier.sh
│   └── tests/
└── lab_75/
```

`lab_75` сохраняет форму инфраструктуры из предыдущих уроков.

`scripts/` — operator/helper слой, как в уроке 74. Эти скрипты не заменяют `policies/`; они помогают запускать локальные проверки, генерировать promotion evidence и готовить reviewer notes.

---

## 5. Уровни риска

| Risk | Значение | Примеры | Approval |
| --- | --- | --- | --- |
| `NO_CHANGE` | управляемых изменений нет | plan содержит только `no-op` | approval не нужен |
| `LOW` | небольшое обратимое изменение, обычно только в `dev` | изменение tag/description в `dev` | обычный env approval |
| `MEDIUM` | заметное изменение инфраструктуры или warnings | изменение в `stage`, NAT warning, изменение ASG/launch template | reviewer approval |
| `HIGH` | `prod`, IAM, destroy, replacement или чувствительное изменение | ASG update в `prod`, IAM policy change, approved destroy | senior/manual approval |
| `EMERGENCY` | активный инцидент или break-glass context | `prod` down, recovery apply, incident mitigation | incident approval + record |
| `BLOCKED` | deny или отсутствуют обязательные доказательства | security deny, cost deny, missing promotion evidence, invalid tfplan.json | нет apply |

Важно: `NO_CHANGE` возможен только если входные файлы нормальные:

```text
policy-deny.json есть
policy-warn.json есть
cost-deny.json есть
cost-warn.json есть
tfplan.json валидный
```

Почему? Потому что иначе `{}` или потерянный policy output могли бы выглядеть как “изменений нет”.

Важно: `EMERGENCY` не обходит deny:

```text
EMERGENCY не обходит deny.
EMERGENCY требует INCIDENT_RECORD_FILE.
```

Нужен incident record:

```text
что случилось
кто разрешил
почему нужен emergency path
```

**Самое важное правило приоритетов**

```text
BLOCKED > EMERGENCY > HIGH > MEDIUM > LOW > NO_CHANGE
```

Это значит:

```text
если есть deny -> BLOCKED
даже если INCIDENT_MODE=true
```

```text
если active incident и evidence есть -> EMERGENCY
даже если там destroy/replacement
```

```text
если prod -> минимум HIGH
```

```text
если stage/warning -> минимум MEDIUM
```

```text
если нет изменений -> NO_CHANGE
но только после валидных inputs
```

Правило:

```text
Deny means stop.
Risk значит: выбери подходящий уровень approval.
Fail closed: если обязательные policy/cost outputs отсутствуют или повреждены, risk должен стать BLOCKED.
```

---

## 6. Входные данные для risk classifier

`policies/risk-classifier.sh` читает:

```text
tfplan.json
target_env
policy-results/policy-deny.json
policy-results/policy-warn.json
cost-policy-results/cost-deny.json
cost-policy-results/cost-warn.json
PROMOTION_EVIDENCE_FILE
INCIDENT_MODE
INCIDENT_RECORD_FILE
RELEASE_ID
SOURCE_ENV
ALLOW_MISSING_POLICY_OUTPUTS
```

### `tfplan.json`

Это машинный Terraform plan:

```bash
terraform show -json tfplan > tfplan.json
```

Он нужен, чтобы classifier посчитал:

```text
changed_count
destructive_count
replacement_count
iam_change_count
asg_or_launch_template_change_count
```

То есть classifier смотрит не весь plan глазами, а считает важные классы изменений.

### `target_env`

```text
dev
stage
prod
```

Окружение само по себе влияет на риск.

```text
dev -> может быть LOW
stage -> минимум MEDIUM при изменениях
prod -> минимум HIGH при изменениях
```

Почему?

Потому что одно и то же изменение в разных средах имеет разную цену ошибки.

`policy-deny.json`

Приходит из:

```bash
terraform-plan-policy.sh
```

Если там есть хотя бы один `deny`: -> risk =` BLOCKED`

`policy-warn.json`
Если есть `warning`: -> risk = минимум `MEDIUM`

`cost-deny.json`
Если есть cost `deny`: -> risk = `BLOCKED`

`cost-warn.json`
Если есть cost `warning`: -> risk = минимум `MEDIUM`

### `PROMOTION_EVIDENCE_FILE`

Нужен для `stage/prod`, если есть managed changes.

Он доказывает: что это изменение уже прошло предыдущую среду

Для stage: -> source_env = `dev`

Для prod: -> source_env = `stage`

Теперь evidence проверяется как контракт:

```json
{
  "release_id": "l75-demo",
  "source_env": "dev",
  "status": "passed",
  "commit_sha": "0123456789abcdef0123456789abcdef01234567"
}
```

Важно: что файл просто существует -> недостаточно -> Он должен быть валидным.

### `INCIDENT_MODE`

Если:

```bash
INCIDENT_MODE=true
```

то classifier может дать: -> `EMERGENCY`

Но только если есть: -> `INCIDENT_RECORD_FILE`

### `INCIDENT_RECORD_FILE`

Это доказательство break-glass:

- какой incident
- какая severity
- почему emergency path
- кто разрешил

Пока в уроке проверяется только наличие непустого файла.

### `Fail-closed входов`
Самый важный принцип:

```text
если обязательный input отсутствует или битый -> BLOCKED
```

Например:

- нет `policy-deny.json`
- нет `cost-warn.json`
- `policy-deny.json` это `{}`, а не `[]`
- `tfplan.json` это `{}`, а не Terraform plan

Всё это должно блокировать `apply`.

Главные сигналы:

| Сигнал | Влияние на риск |
| --- | --- |
| отсутствует или повреждён обязательный policy/cost output | `BLOCKED` |
| security/cost deny | `BLOCKED` |
| missing/invalid promotion evidence для `stage`/`prod`, если есть managed changes | `BLOCKED` |
| incident mode с incident record | `EMERGENCY`, если нет deny |
| incident mode без incident record | `BLOCKED` |
| окружение `prod` | `HIGH` |
| IAM change | `HIGH` |
| destroy/replacement | `HIGH` |
| policy/cost warning | минимум `MEDIUM` |
| изменение ASG/launch template | минимум `MEDIUM` |
| окружение `stage` | минимум `MEDIUM` |
| нет managed resource changes | `NO_CHANGE` |
| маленькое изменение только в `dev` | `LOW` |

Приоритеты применяются сверху вниз:

```text
BLOCKED > EMERGENCY > HIGH > MEDIUM > LOW > NO_CHANGE
```

Это значит:

- `BLOCKED` всегда сильнее остальных уровней;
- `EMERGENCY` не обходит deny и не работает без `INCIDENT_RECORD_FILE`;
- `HIGH` сильнее `MEDIUM` и `LOW`;
- `NO_CHANGE` возможен только если обязательные входные файлы существуют и корректны.

Classifier также разделяет два решения:

- `risk` — насколько опасно изменение;
- `approval_required` и `approval_level` — нужен ли approval и какой именно.

Так проще автоматизировать pipeline: машина читает `apply_allowed`, `approval_required` и `approval_level`, а человек читает `reason_codes`.

Promotion evidence проверяется как контракт, а не как “файл существует”. Если evidence нужен, classifier ожидает JSON object с:

- `release_id` — должен совпадать с `RELEASE_ID`, если он передан;
- `source_env` — должен совпадать с `SOURCE_ENV`, если он передан;
- `status` — должен быть `passed`;
- `commit_sha` — должен выглядеть как Git SHA.

---

## 7. Risk classifier

Запуск напрямую:

```bash
lessons/75-apply-risk-classification-and-change-review/policies/risk-classifier.sh tfplan.json dev
```

Полезные environment variables:

```bash
POLICY_DIR=policy-results
COST_DIR=cost-policy-results
OUT_DIR=risk-results
INCIDENT_MODE=false
INCIDENT_RECORD_FILE=/tmp/incident-record.md
RELEASE_ID=l75-demo
SOURCE_ENV=dev
PROMOTION_EVIDENCE_FILE=/tmp/promotion-evidence.json
REQUIRE_PROMOTION_EVIDENCE=true
ALLOW_MISSING_POLICY_OUTPUTS=false
```

Смысл простой: это финальный “сборщик решения”. Он не сам ищет все проблемы с нуля, а берёт уже подготовленные входы:

```text
terraform plan -> tfplan.json
terraform-plan-policy.sh -> policy-deny.json / policy-warn.json
cost-policy.sh -> cost-deny.json / cost-warn.json
promotion-evidence-template.sh или CI artifact -> promotion-evidence.json
incident record -> только если INCIDENT_MODE=true
target_env -> второй аргумент dev/stage/prod
risk-classifier.sh -> risk-decision.json / risk-decision.md
```

Ручная цепочка для реального plan из `dev`:

```bash
cd lessons/75-apply-risk-classification-and-change-review/lab_75/terraform/envs/dev

terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json

mkdir -p ../../../../evidence/policy-results \
         ../../../../evidence/cost-policy-results \
         ../../../../evidence/risk-results

OUT_DIR=../../../../evidence/policy-results \
../../../../policies/terraform-plan-policy.sh tfplan.json

OUT_DIR=../../../../evidence/cost-policy-results \
../../../../policies/cost-policy.sh tfplan.json dev

POLICY_DIR=../../../../evidence/policy-results \
COST_DIR=../../../../evidence/cost-policy-results \
OUT_DIR=../../../../evidence/risk-results \
REQUIRE_PROMOTION_EVIDENCE=false \
../../../../policies/risk-classifier.sh tfplan.json dev
```

И превращает их в один итог:

```text
risk-decision.json
risk-decision.md
```

`risk-decision.json` содержит:

- `risk`;
- `apply_allowed`;
- `approval_required`;
- `approval_level`;
- `promotion_present`;
- `promotion_valid`;
- `reason_codes`;
- счётчики destructive/replacement/IAM/policy/cost signals;
- `fail_closed: true`.

То есть вместо того чтобы reviewer вручную открывал 5 разных файлов classifier собирает ответ:

```text
Risk: HIGH
Apply allowed: true
Approval required: true
Reason codes:
- target_env_prod
- iam_change
- replacement_change
```

Ключевая модель:

- policy/cost outputs = сигналы
- risk-classifier = финальное решение

Разбор важных переменных:


```bash
INCIDENT_MODE=false
```

Если `true`, то это emergency/break-glass сценарий. Но важно:

```text
INCIDENT_MODE=true не обходит deny
```

Если есть deny, всё равно будет `BLOCKED`.

```bash
PROMOTION_EVIDENCE_FILE=/tmp/promotion-evidence.json
```

Файл, который доказывает, что изменение прошло предыдущую среду.

Например для `prod` он должен доказывать, что `stage` уже прошёл успешно.

```bash
REQUIRE_PROMOTION_EVIDENCE=true
```

Если `stage/prod`, evidence должен быть. Иначе это fail-closed.

```bash
ALLOW_MISSING_POLICY_OUTPUTS=false
```

Если policy output файлов нет, classifier не должен думать:

```text
нет файлов = нет проблем
```

Правильно:

```text
нет файлов = проверка сломана = BLOCKED
```

Это и есть `fail closed`.

Exit codes:

```text
0  -> risk gate разрешил продолжить
1  -> сломался input/tooling
2  -> risk gate заблокировал apply
64 -> неправильно вызвали скрипт
```

---

## 8. Связь риска и approval

| Risk | Apply разрешён? | Рекомендуемый путь approval |
| --- | --- | --- |
| `NO_CHANGE` | да | approval не нужен |
| `LOW` | да | обычный env approval |
| `MEDIUM` | да | reviewer или stage environment |
| `HIGH` | да | senior reviewer / high-risk environment |
| `EMERGENCY` | да, только с incident record | break-glass / incident approval |
| `BLOCKED` | нет | нет |

Смысл раздела: `risk` сам по себе не применяет инфраструктуру. Он говорит, какой уровень проверки нужен перед `apply`.

Самое важное здесь:

```text
apply_allowed=true
```

не равно:

```text
можно сразу нажимать apply
```

Это значит только:

```text
risk gate не заблокировал изменение
```

Но если:

```text
approval_required=true
```

то нужен человек или GitHub Environment approval.

Пример:

```text
Risk: HIGH
Apply allowed: true
Approval required: true
Reason Codes:
- iam_change
```

Это означает:

```text
Policy deny нет.
Cost deny нет.
Но есть IAM changes.
Значит apply технически допустим, но только после high-risk review.
```

Почему так правильно:

```text
deny/block = изменение запрещено
risk/approval = изменение разрешено, но требует контроля
```

Поэтому мы разделяем:

```text
risk
apply_allowed
approval_required
approval_level
```

Пример:

```json
{
  "risk": "HIGH",
  "apply_allowed": true,
  "approval_required": true,
  "approval_level": "senior_reviewer_or_high_risk_environment"
}
```

Это читается так:

```text
Изменение рискованное, но не запрещённое.
Apply возможен только после senior/high-risk approval.
```

А вот `BLOCKED`:

```json
{
  "risk": "BLOCKED",
  "apply_allowed": false,
  "approval_required": false,
  "approval_level": "none"
}
```

Это читается так:

```text
Изменение запрещено.
Approval не нужен, потому что approve нечего.
Сначала исправь plan/policy/evidence.
```

GitHub Environment модель:

```text
terraform-dev
terraform-stage
terraform-prod
terraform-high-risk
terraform-break-glass
```

Идея такая:
- обычный `dev` apply может идти через `terraform-dev`;
- `stage` через `terraform-stage`;
- `prod` через `terraform-prod`;
- `HIGH` можно отправлять в отдельный `terraform-high-risk`;
- `EMERGENCY` в `terraform-break-glass`.

В уроке реализация остаётся простой: classifier создаёт artifact, а reviewer использует его перед approval `apply`.

---

## 9. Модель CI

- `ci/lesson75-real-plan-risk-review.yml` — реальный AWS-backed plan через OIDC и remote backend. Активная копия лежит в `.github/workflows/lesson75-real-plan-risk-review.yml`.

Workflow не делает `apply`.

Правильный порядок для реального apply pipeline:

```text
fmt/test/validate
-> terraform plan -out=tfplan
-> terraform show -json tfplan
-> security policy
-> cost policy
-> risk classifier
-> upload plan/policy/risk artifacts
-> environment approval
-> apply exact tfplan
-> post-apply drift check
```

Важно:

```text
Risk decision должен существовать до ручного approval.
```

Reviewer должен видеть:

- `tfplan.txt`;
- `policy-decision.txt`;
- `cost-decision.txt`;
- `risk-decision.md`;
- promotion evidence для `stage`/`prod`.

Real plan workflow делает:

```text
OIDC assume plan role
-> write backend.hcl / terraform.auto.tfvars
-> terraform init с S3 backend
-> terraform plan -out=tfplan
-> terraform show -json tfplan
-> security policy
-> cost policy
-> risk classifier
-> upload real plan/policy/cost/risk artifacts
```

Нужные repository variables:

```text
AWS_REGION
TF_STATE_BUCKET
TF_WEB_AMI_ID
TF_SSM_PROXY_AMI_ID
TF_GITHUB_OIDC_PROVIDER_ARN
TF_PLAN_ROLE_ARN_DEV
TF_PLAN_ROLE_ARN_STAGE
TF_PLAN_ROLE_ARN_PROD
```

Для `dev` promotion evidence не нужен. Для `stage` и `prod` workflow требует repo-relative `promotion_evidence_path`, чтобы classifier мог проверить promotion context.

В CI есть дополнительные защиты:

- `ALLOW_MISSING_POLICY_OUTPUTS=true` явно запрещён в CI;
- глобальный `REQUIRE_PROMOTION_EVIDENCE=false` явно запрещён в CI;
- policy/cost exit `2` не останавливает сбор risk artifact, но tooling errors останавливают job;
- `risk-classifier` остаётся финальным gate: если risk `BLOCKED`, workflow падает после сохранения artifacts.

---

## 10. Локальные тесты

Запусти унаследованные проверки и risk tests:

```bash
lessons/75-apply-risk-classification-and-change-review/policies/test-policy.sh
lessons/75-apply-risk-classification-and-change-review/policies/test-cost-policy.sh
lessons/75-apply-risk-classification-and-change-review/policies/test-risk-classifier.sh
lessons/75-apply-risk-classification-and-change-review/policies/test-opa.sh
```

Risk tests проверяют:

- no-change plan -> `NO_CHANGE`;
- безопасное изменение в dev -> `LOW`;
- stage NAT warning с доказательствами -> `MEDIUM`;
- prod change с доказательствами -> `HIGH`;
- invalid promotion evidence -> `BLOCKED`;
- policy deny -> `BLOCKED`;
- отсутствующие или битые policy/cost outputs -> `BLOCKED`;
- incident mode -> `EMERGENCY`;
- incident mode без incident record -> `BLOCKED`;
- отсутствие promotion evidence для stage с managed changes -> `BLOCKED`.

---

## 11. Практические упражнения

Все упражнения выполняются локально на синтетических `tfplan.json` fixtures. AWS-доступ не нужен.

Из корня репозитория:

```bash
cd lessons/75-apply-risk-classification-and-change-review
```

Подготовь временные файлы:

```bash
mkdir -p /tmp/l75-review

cat > /tmp/l75-review/promotion-evidence-stage.json <<'EOF'
{
  "release_id": "l75-demo",
  "source_env": "dev",
  "status": "passed",
  "workflow_run_url": "https://example.invalid/workflow",
  "commit_sha": "0123456789abcdef0123456789abcdef01234567"
}
EOF

cat > /tmp/l75-review/promotion-evidence-prod.json <<'EOF'
{
  "release_id": "l75-demo",
  "source_env": "stage",
  "status": "passed",
  "workflow_run_url": "https://example.invalid/workflow",
  "commit_sha": "0123456789abcdef0123456789abcdef01234567"
}
EOF

cat > /tmp/l75-review/incident-record.md <<'EOF'
# Incident Record

- Incident ID: INC-L75-001
- Severity: SEV-2
- Reason: lesson 75 emergency-mode drill
- Approval: simulated
EOF
```

### Упражнение 1. Low-risk change в dev

Используй `safe-plan.json` с target env `dev`.

```bash
rm -rf /tmp/l75-review/low-dev
mkdir -p /tmp/l75-review/low-dev/policy /tmp/l75-review/low-dev/cost
printf '[]\n' > /tmp/l75-review/low-dev/policy/policy-deny.json
printf '[]\n' > /tmp/l75-review/low-dev/policy/policy-warn.json
printf '[]\n' > /tmp/l75-review/low-dev/cost/cost-deny.json
printf '[]\n' > /tmp/l75-review/low-dev/cost/cost-warn.json

POLICY_DIR=/tmp/l75-review/low-dev/policy \
COST_DIR=/tmp/l75-review/low-dev/cost \
OUT_DIR=/tmp/l75-review/low-dev/risk \
REQUIRE_PROMOTION_EVIDENCE=false \
policies/risk-classifier.sh policies/tests/safe-plan.json dev
```

Ожидаемо:

```text
Risk: LOW
Approval required: true
Approval level: standard
Apply allowed: true
Promotion required: true
Promotion present: false
Promotion valid: false
Reason Codes:
- small_dev_change
```

### Упражнение 2. Medium-risk warning в stage

Используй `cost-nat-plan.json` с target env `stage` и файлом promotion evidence.

```bash
rm -rf /tmp/l75-review/medium-stage
mkdir -p /tmp/l75-review/medium-stage/policy /tmp/l75-review/medium-stage/cost

OUT_DIR=/tmp/l75-review/medium-stage/policy \
policies/terraform-plan-policy.sh policies/tests/cost-nat-plan.json || true

OUT_DIR=/tmp/l75-review/medium-stage/cost \
policies/cost-policy.sh policies/tests/cost-nat-plan.json stage || true

POLICY_DIR=/tmp/l75-review/medium-stage/policy \
COST_DIR=/tmp/l75-review/medium-stage/cost \
OUT_DIR=/tmp/l75-review/medium-stage/risk \
PROMOTION_EVIDENCE_FILE=/tmp/l75-review/promotion-evidence-stage.json \
RELEASE_ID=l75-demo \
SOURCE_ENV=dev \
policies/risk-classifier.sh policies/tests/cost-nat-plan.json stage
```

Ожидаемо:

```text
Risk: MEDIUM
Approval required: true
Approval level: reviewer_or_stage_environment
Apply allowed: true
Promotion required: true
Promotion present: true
Promotion valid: true
Reason Codes:
- target_env_stage
- warnings_present
```

### Упражнение 3. High-risk change в prod

Используй safe plan с target env `prod` и файлом promotion evidence.

```bash
rm -rf /tmp/l75-review/high-prod
mkdir -p /tmp/l75-review/high-prod/policy /tmp/l75-review/high-prod/cost
printf '[]\n' > /tmp/l75-review/high-prod/policy/policy-deny.json
printf '[]\n' > /tmp/l75-review/high-prod/policy/policy-warn.json
printf '[]\n' > /tmp/l75-review/high-prod/cost/cost-deny.json
printf '[]\n' > /tmp/l75-review/high-prod/cost/cost-warn.json

POLICY_DIR=/tmp/l75-review/high-prod/policy \
COST_DIR=/tmp/l75-review/high-prod/cost \
OUT_DIR=/tmp/l75-review/high-prod/risk \
PROMOTION_EVIDENCE_FILE=/tmp/l75-review/promotion-evidence-prod.json \
RELEASE_ID=l75-demo \
SOURCE_ENV=stage \
policies/risk-classifier.sh policies/tests/safe-plan.json prod
```

Ожидаемо:

```text
Risk: HIGH
Approval required: true
Approval level: senior_reviewer_or_prod_environment
Apply allowed: true
Reason Codes:
- target_env_prod
```

### Упражнение 4. Blocked public ingress

Используй `public-ingress-plan.json` с target env `dev`.

```bash
rm -rf /tmp/l75-review/blocked-ingress
mkdir -p /tmp/l75-review/blocked-ingress/policy /tmp/l75-review/blocked-ingress/cost

OUT_DIR=/tmp/l75-review/blocked-ingress/policy \
policies/terraform-plan-policy.sh policies/tests/public-ingress-plan.json || true

printf '[]\n' > /tmp/l75-review/blocked-ingress/cost/cost-deny.json
printf '[]\n' > /tmp/l75-review/blocked-ingress/cost/cost-warn.json

POLICY_DIR=/tmp/l75-review/blocked-ingress/policy \
COST_DIR=/tmp/l75-review/blocked-ingress/cost \
OUT_DIR=/tmp/l75-review/blocked-ingress/risk \
REQUIRE_PROMOTION_EVIDENCE=false \
policies/risk-classifier.sh policies/tests/public-ingress-plan.json dev || true
```

Ожидаемо:

```text
Risk: BLOCKED
Approval required: false
Approval level: none
Apply allowed: false
Security policy denies: 1
Reason Codes:
- policy_or_cost_deny_present
```

### Упражнение 5. Emergency mode

Запусти classifier с:

```bash
INCIDENT_MODE=true
INCIDENT_RECORD_FILE=/tmp/incident-record.md
```

Команда:

```bash
rm -rf /tmp/l75-review/emergency
mkdir -p /tmp/l75-review/emergency/policy /tmp/l75-review/emergency/cost
printf '[]\n' > /tmp/l75-review/emergency/policy/policy-deny.json
printf '[]\n' > /tmp/l75-review/emergency/policy/policy-warn.json
printf '[]\n' > /tmp/l75-review/emergency/cost/cost-deny.json
printf '[]\n' > /tmp/l75-review/emergency/cost/cost-warn.json

POLICY_DIR=/tmp/l75-review/emergency/policy \
COST_DIR=/tmp/l75-review/emergency/cost \
OUT_DIR=/tmp/l75-review/emergency/risk \
INCIDENT_MODE=true \
INCIDENT_RECORD_FILE=/tmp/l75-review/incident-record.md \
REQUIRE_PROMOTION_EVIDENCE=false \
policies/risk-classifier.sh policies/tests/safe-plan.json dev
```

Ожидаемо:

```text
Risk: EMERGENCY
Approval required: true
Approval level: incident_commander_and_break_glass
Apply allowed: true
Incident mode: true
Incident record required: true
Incident record present: true
Reason Codes:
- incident_mode_enabled
```

Контрпример:

```bash
OUT_DIR=/tmp/l75-review/emergency-missing-record/risk \
POLICY_DIR=/tmp/l75-review/emergency/policy \
COST_DIR=/tmp/l75-review/emergency/cost \
INCIDENT_MODE=true \
REQUIRE_PROMOTION_EVIDENCE=false \
policies/risk-classifier.sh policies/tests/safe-plan.json dev || true
```

Ожидаемо: `BLOCKED` и reason `incident_record_missing`.

### Упражнение 6. Missing promotion evidence

Запусти classifier для `stage` или `prod` без `PROMOTION_EVIDENCE_FILE`.

```bash
rm -rf /tmp/l75-review/missing-promotion
mkdir -p /tmp/l75-review/missing-promotion/policy /tmp/l75-review/missing-promotion/cost
printf '[]\n' > /tmp/l75-review/missing-promotion/policy/policy-deny.json
printf '[]\n' > /tmp/l75-review/missing-promotion/policy/policy-warn.json
printf '[]\n' > /tmp/l75-review/missing-promotion/cost/cost-deny.json
printf '[]\n' > /tmp/l75-review/missing-promotion/cost/cost-warn.json

POLICY_DIR=/tmp/l75-review/missing-promotion/policy \
COST_DIR=/tmp/l75-review/missing-promotion/cost \
OUT_DIR=/tmp/l75-review/missing-promotion/risk \
RELEASE_ID=l75-demo \
SOURCE_ENV=dev \
policies/risk-classifier.sh policies/tests/safe-plan.json stage || true
```

Ожидаемо:

```text
Risk: BLOCKED
Approval required: false
Approval level: none
Apply allowed: false
Promotion required: true
Promotion present: false
Promotion valid: false
Reason Codes:
- promotion_evidence_missing
```

### Упражнение 7. No-change plan

Используй fixture, где managed resources не меняются.

```bash
rm -rf /tmp/l75-review/no-change
mkdir -p /tmp/l75-review/no-change/policy /tmp/l75-review/no-change/cost
printf '[]\n' > /tmp/l75-review/no-change/policy/policy-deny.json
printf '[]\n' > /tmp/l75-review/no-change/policy/policy-warn.json
printf '[]\n' > /tmp/l75-review/no-change/cost/cost-deny.json
printf '[]\n' > /tmp/l75-review/no-change/cost/cost-warn.json

POLICY_DIR=/tmp/l75-review/no-change/policy \
COST_DIR=/tmp/l75-review/no-change/cost \
OUT_DIR=/tmp/l75-review/no-change/risk \
REQUIRE_PROMOTION_EVIDENCE=false \
policies/risk-classifier.sh policies/tests/no-op-warn-plan.json dev
```

Ожидаемо:

```text
Risk: NO_CHANGE
Approval required: false
Approval level: none
Apply allowed: true
Changed resources: 0
Reason Codes:
- no_managed_resource_changes
```

Смысл:

- если Terraform не собирается менять managed resources, approval не нужен;
- но это разрешено только если policy/cost outputs существуют и валидны;
- иначе {} или сломанный pipeline мог бы ошибочно стать NO_CHANGE.

### Упражнение 8. Fail closed при отсутствующих outputs

Запусти classifier без `policy-deny.json`, `policy-warn.json`, `cost-deny.json`, `cost-warn.json`.

```bash
rm -rf /tmp/l75-review/fail-closed
mkdir -p /tmp/l75-review/fail-closed/policy /tmp/l75-review/fail-closed/cost

POLICY_DIR=/tmp/l75-review/fail-closed/policy \
COST_DIR=/tmp/l75-review/fail-closed/cost \
OUT_DIR=/tmp/l75-review/fail-closed/risk \
REQUIRE_PROMOTION_EVIDENCE=false \
policies/risk-classifier.sh policies/tests/safe-plan.json dev || true
```

Ожидаемо:

- risk `BLOCKED`;
- `apply_allowed=false`;
- reason содержит `policy_deny_missing`, `policy_warn_missing`, `cost_deny_missing`, `cost_warn_missing`.

---

## 12. Разбор проблем

| Симптом | Вероятная причина | Что делать |
| --- | --- | --- |
| risk стал `BLOCKED` | есть deny или отсутствуют доказательства | смотри reasons в `risk-decision.md` |
| safe plan стал `BLOCKED` | отсутствуют или повреждены policy/cost outputs | сначала запусти security/cost policy или проверь `POLICY_DIR`/`COST_DIR` |
| `stage`/`prod` неожиданно `BLOCKED` | нет `PROMOTION_EVIDENCE_FILE` или evidence не прошёл contract | проверь `release_id`, `source_env`, `status`, `commit_sha` |
| risk выше ожидаемого | env, IAM, destroy, replacement или warning подняли risk | проверь counters в `risk-decision.json` |
| risk стал `NO_CHANGE` | в plan нет managed resource changes | проверь, что это ожидаемый plan и не перепутан fixture/artifact |
| classifier завершился с `64` на `tfplan.json` | это не Terraform JSON plan или нет `resource_changes[].change.actions` | пересоздай JSON через `terraform show -json tfplan` |
| classifier завершился с `64` | неверные args/env values | проверь usage и target env |
| emergency mode используется слишком легко | нет incident record | требуй break-glass evidence |
| policy разрешила change, но risk высокий | plan разрешён, но изменение чувствительное | используй более строгий approval |

---

## 13. Критерии успеха

Урок завершён, если:

- risk classifier существует и исполняемый;
- classifier читает outputs policy/cost;
- classifier работает по fail-closed модели для отсутствующих/битых inputs;
- classifier отклоняет JSON, который не похож на Terraform plan;
- classifier создаёт `risk-decision.json` и `risk-decision.md`;
- no-change plan становится `NO_CHANGE`;
- безопасное изменение в dev становится `LOW`;
- stage warning становится `MEDIUM`;
- prod change становится `HIGH`;
- invalid promotion evidence становится `BLOCKED`;
- policy deny становится `BLOCKED`;
- incident mode становится `EMERGENCY`;
- incident mode без incident record становится `BLOCKED`;
- missing promotion evidence блокирует stage/prod, если есть managed changes;
- risk artifact доступен до approval;

---

## 14. Итоги урока

- **Что изучил:** разрешённые plans всё равно требуют risk classification.
- **Что практиковал:** объединение данных Terraform actions, outputs policy/cost, окружения, promotion evidence и incident mode в один artifact для ревью.
- **Главная защита:** classifier должен fail closed, а не делать вид, что всё безопасно при потере входных данных.
- **Операционный фокус:** approval должен соответствовать уровню risk.
