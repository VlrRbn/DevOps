# Capstone: End-to-End Terraform Delivery Pipeline

**Дата:** 2026-06-28

**Фокус:** связать предыдущие уроки по доставке Terraform в один контролируемый release process: локальные проверки, module tests, plan artifacts, policy gates, cost gates, risk classification, approval, exact-plan apply, post-apply verification, runtime health evidence и proof pack.

**Подход:** этот урок не добавляет новую возможность. Он доказывает, что вся delivery-система работает как единый процесс.

---

## 1. Зачем нужен этот урок

В предыдущих уроках ты собрал отдельные части:

```text
remote state -> module contracts -> native tests -> PR plan -> policy gates -> cost gates -> risk review -> controlled apply -> promotion -> drift checks -> incident runbooks
```

Итоговый урок связывает всё в один операционный вопрос:

```text
Могу ли я доказать, что именно изменилось, почему это разрешено, кто это проверил, что было применено и чистое ли окружение после apply?
```

Зрелый процесс доставки Terraform — это доказательства, approval, воспроизводимость и готовность к восстановлению.

---

## 2. Результаты урока

После урока ты должен уметь:

- запускать безопасные локальные проверки до PR;
- объяснять разницу между preview plan в PR и apply plan;
- проверять module contracts и root-модули окружений;
- генерировать `tfplan`, `tfplan.txt` и `tfplan.json`;
- запускать security policy и cost/blast-radius policy;
- запускать risk classifier и читать `risk-decision.md`;
- требовать approval с учётом окружения и уровня риска;
- применять точный сохранённый `tfplan`, а не новый plan;
- сохранять доказательства post-apply drift и runtime health;

---

## 3. Связь с предыдущими уроками

| Урок | Что уже есть | Как это использует урок 76 |
| --- | --- | --- |
| 60 | remote state and locking | отдельные backend keys и безопасность state |
| 61 | state hygiene and refactors | дисциплина безопасных изменений state |
| 62 | Terraform quality gates | привычка к fmt/validate/tflint/checkov |
| 63 | CI plan pipeline | PR plan и мышление через artifacts |
| 64 | drift detection | post-apply и scheduled drift checks |
| 65 | secrets and safe inputs | не хранить secrets в repo или artifacts без ревью |
| 66 | module contracts | гарантии интерфейса модуля |
| 67 | native tests | `terraform test` перед release/apply |
| 68 | controlled apply | точный saved plan перед apply |
| 69 | least-privilege roles | отдельные plan/apply roles |
| 70 | JSON plan policy | security policy по `tfplan.json` |
| 71 | multi-env promotion | доказательства для `dev -> stage -> prod` |
| 72 | module release discipline | закреплённая версия модуля и release note thinking |
| 73 | cost/blast-radius controls | cost policy и blast-radius warnings |
| 74 | incident runbooks | процедура восстановления и runtime evidence |
| 75 | risk classification | финальное решение `LOW/MEDIUM/HIGH/EMERGENCY/BLOCKED` |

---

## 4. Структура репозитория

```text
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/
├── README.md
├── lesson.en.md
├── lesson.ru.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   ├── lesson76-pr-checks.yml
│   ├── lesson76-capstone-promote.yml
│   └── lesson76-drift-check.yml
├── scripts/
│   ├── run-local-checks.sh
│   ├── promotion-evidence-template.sh
│   ├── reviewer-note-template.sh
│   ├── write-terraform-env-files.sh
│   ├── runtime-health-check.sh
│   ├── state-snapshot.sh
│   ├── post-incident-check.sh
│   ├── collect-capstone-proof.sh
│   └── summarize-capstone.sh
├── policies/
│   ├── security-policy.sh
│   ├── cost-policy.sh
│   ├── risk-classifier.sh
│   └── tests/
├── runbooks/
└── lab_76/
    ├── packer/
    └── terraform/
        ├── backend-bootstrap/
        ├── envs/dev/
        ├── envs/stage/
        ├── envs/prod/
        └── modules/network/
```

`ci/` содержит шаблоны. Копируй их в `.github/workflows/` только когда готов подключать урок к GitHub Actions.

---

## 5. Финальная delivery-модель

```text
PR checks
  -> fmt / validate / module tests / policy tests
  -> optional PR plan preview

merge to main
  -> choose target environment
  -> verify promotion evidence
  -> create saved tfplan
  -> render tfplan.txt and tfplan.json
  -> run security policy
  -> run cost policy
  -> run risk classifier
  -> upload review artifacts
  -> wait for GitHub Environment approval
  -> apply exact tfplan
  -> post-apply plan -detailed-exitcode
  -> runtime health check
  -> proof pack
```

Ключевое различие:

```text
PR plan = предварительный план для ревью.
Apply plan = новый saved plan из protected branch, который применяется точно как сохранён.
```

Не применяй старый PR artifact вслепую.

`tfplan.sha256` нужен, чтобы поймать случайную подмену или несовпадение файла внутри review package. Это не полноценная security boundary: если атакующий может заменить весь artifact, он может заменить и checksum. Основная защита здесь — protected branch, GitHub Environment approval, least-privilege roles, короткий retention и, при необходимости, artifact attestation.

---

## 6. Контрольные проверки

| Gate | Обязательные доказательства | Отвечает на один вопрос? |
| --- | --- | --- |
| Local quality | вывод `scripts/run-local-checks.sh` | код вообще нормально выглядит? |
| Module contract | вывод `terraform test` | модуль не сломал свой интерфейс? |
| Environment validation | `terraform validate` для `dev`, `stage`, `prod` | root-модуль окружения валиден для dev/stage/prod? |
| Backend isolation | `backend.hcl` использует правильный state key | state key правильный и окружения не трут друг друга? |
| Plan artifact | `tfplan`, `tfplan.txt`, `tfplan.json` | есть точный `tfplan`, читаемый `tfplan.txt`, машинный `tfplan.json`? |
| Security policy | `policy-decision.txt`, `policy-deny.json`, `policy-warn.json` | нет запрещённых изменений? |
| Cost policy | `cost-decision.txt`, `cost-deny.json`, `cost-warn.json` | нет cost/blast-radius нарушения? |
| Risk review | `risk-decision.json`, `risk-decision.md` | можно ли apply, какой risk level, нужен ли approval? |
| Approval | GitHub Environment approval или ручной reviewer note | человек или GitHub Environment gate разрешил? |
| Apply | `apply.txt` от `terraform apply tfplan` | применён точный saved plan? |
| Drift check | `post_apply_exitcode.txt` равен `0` | после apply Terraform видит clean state? |
| Runtime health | target health, ASG health, alarm state evidence | сервис реально здоров, а не только Terraform доволен? |
| Recovery readiness | нужный runbook есть до risky apply | есть runbook, если apply пойдёт плохо? |

---

## 7. Локальные проверки

Запуск из корня репозитория:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
```

Опциональные проверки:

```bash
RUN_OPA=true lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
RUN_TERRAFORM=true lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
```

`RUN_TERRAFORM=true` может потребовать доступ к Terraform provider/plugin registry, если локальный plugin cache пустой.

---

## 8. Ручной capstone-flow

Используй этот процесс для локальной практики до подключения GitHub Actions.

`backend.hcl` и `terraform.tfvars` не коммитятся. Для локальной работы создай их из `.example` файлов и подставь свои значения:

```bash
cd lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

В CI эти файлы создаёт `scripts/write-terraform-env-files.sh` из GitHub Variables. Так workflow не зависит от локальных игнорируемых файлов.

```bash
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive ../..
terraform validate
terraform plan -out=tfplan
terraform show -no-color tfplan > tfplan.txt
terraform show -json tfplan > tfplan.json
sha256sum tfplan > tfplan.sha256
```

Запусти policy gates из корня репозитория:

```bash
OUT_DIR=/tmp/l76-policy \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/security-policy.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev/tfplan.json

OUT_DIR=/tmp/l76-cost \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/cost-policy.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev/tfplan.json \
  dev
```

Запусти risk review:

```bash
POLICY_DIR=/tmp/l76-policy \
COST_DIR=/tmp/l76-cost \
OUT_DIR=/tmp/l76-risk \
REQUIRE_PROMOTION_EVIDENCE=false \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/risk-classifier.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev/tfplan.json \
  dev
```

Сгенерируй reviewer note:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/reviewer-note-template.sh \
  /tmp/l76-risk/risk-decision.json \
  > /tmp/l76-reviewer-note.md
```

Только после ревью применяй точный plan:

```bash
terraform apply tfplan
terraform plan -detailed-exitcode -input=false -no-color > post_apply_plan.txt
printf '%s\n' "$?" > post_apply_exitcode.txt
```

---

## 9. Доказательства продвижения (promotion)

Для managed changes в `stage` и `prod` нужны доказательства promotion.

Promotion evidence должно доказать:

- это изменение уже прошло предыдущую среду
- на том же `commit SHA`
- с тем же `release_id`
- source run завершился `success`
- `source_workflow_run_url`
  -> GitHub API
  -> status `completed`
  -> conclusion `success`
  -> `head_sha == current GITHUB_SHA`

Сгенерируй шаблон:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/promotion-evidence-template.sh \
  l76-demo \
  dev \
  "$(git rev-parse HEAD)" \
  "https://github.com/OWNER/REPO/actions/runs/123456789" \
  > /tmp/promotion-evidence-stage.json
```

Минимальные поля:

```json
{
  "release_id": "l76-demo",
  "source_env": "dev",
  "status": "passed",
  "commit_sha": "...",
  "source_workflow_run_url": "https://github.com/OWNER/REPO/actions/runs/..."
}
```

Для `prod` source environment обычно должен быть `stage`.

---

## 10. Доказательства runtime health

Terraform после `apply` может быть clean, но сервис всё равно может не работать:

- ASG создан, но instances unhealthy
- ALB есть, но target group unhealthy
- CloudWatch alarm в `ALARM`
- SSM endpoint есть, но session не работает
- nginx не стартовал
- `user_data` сломался
- security group разрешает не то

После apply собери read-only runtime evidence:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/runtime-health-check.sh dev
```

Скрипт читает Terraform outputs и проверяет:

- ALB target health;
- ASG instance health;
- CloudWatch alarm states.

Он не меняет инфраструктуру или state.

---

## 11. Доказательства incident/recovery

Перед recovery сохрани текущие доказательства:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/state-snapshot.sh dev
```

После recovery сохрани post-incident status плана:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/post-incident-check.sh dev
```

Используй runbooks в `runbooks/` для:

- failed apply;
- stuck lock;
- state restore;
- break-glass;
- rollback vs fix-forward;
- drift after emergency.

---

## 12. Шаблоны CI

В уроке есть три шаблона:

| Файл | Назначение |
| --- | --- |
| `ci/lesson76-pr-checks.yml` | безопасные PR checks: fmt, scripts, policies, module tests |
| `ci/lesson76-capstone-promote.yml` | controlled promotion skeleton: plan artifacts до approval, exact-plan apply после approval |
| `ci/lesson76-drift-check.yml` | scheduled/manual read-only drift detection, который падает при exit code `2` |

### Capstone promote

Plan job:

```text
validate inputs
checkout exact commit
local checks
verify source workflow run через GitHub API
assume plan role
generate backend/tfvars
terraform init/validate/plan
policy gates
cost gates
risk classifier
upload review artifact
fail if apply_allowed=false
```

Apply job:

```text
GitHub Environment approval
download reviewed artifact
assume apply role
restore backend/tfvars
init
sha256 check
terraform apply exact tfplan
post-apply drift check
upload apply artifact even on failure
```

### Drift check

Read-only workflow:

```text
schedule/manual
assume plan role
generate backend/tfvars
init
fmt/validate
terraform plan -detailed-exitcode -out=tfplan
upload drift evidence
fail on exit code 2
```

Promote template намеренно консервативный. Перед использованием против реального AWS проверь:

- GitHub OIDC provider существует;
- GitHub Actions pinned by commit SHA и обновляются отдельным ревью;
- `TF_PLAN_ROLE_ARN_*` variables заданы;
- `TF_APPLY_ROLE_ARN_*` environment secrets заданы;
- `TF_STATE_BUCKET`, `TF_WEB_AMI_ID`, `TF_SSM_PROXY_AMI_ID`, `TF_GITHUB_OIDC_PROVIDER_ARN` variables заданы;
- backend bucket/key корректные и генерируются из CI, а не берутся из Git;
- GitHub Environments требуют reviewers для `stage`/`prod`;
- сгенерированные artifacts проверяются до approval;
- `source_workflow_run_url` для `stage`/`prod` указывает на предыдущий environment run и проверяется через GitHub API;
- заблокированный risk всё равно должен сохранять review artifact, чтобы ревьюер видел причину отказа;
- apply artifact загружается даже при failed apply или failed post-apply check;
- drift workflow использует только plan role, делает `fmt/validate`, сохраняет `tfplan.txt`/`tfplan.json`, не загружает binary `tfplan` и не применяет changes.

---

## 13. Разбор проблем

| Симптом | Вероятная причина | Что проверить |
| --- | --- | --- |
| `terraform init` спрашивает bucket | отсутствует или неверный `backend.hcl` | путь и значения backend file |
| plan role падает | проблема с OIDC, trust policy или role ARN | GitHub variables, IAM trust policy, repo/ref claims |
| policy проходит, но risk `BLOCKED` | не хватает evidence или другой gate вернул deny | reason codes в `risk-decision.md` |
| `stage`/`prod` blocked | нет promotion evidence | `PROMOTION_EVIDENCE_FILE`, `release_id`, `source_env` |
| apply blocked by approval | GitHub Environment protection | reviewers, branch restrictions, environment name |
| apply использует другие changes | fresh plan после approval | применяй только exact saved `tfplan` artifact |
| post-apply exit code `2` | drift или unapplied diff | смотри `post_apply_plan.txt` |
| runtime health unhealthy | проблема с app, ALB, ASG или alarm | target health, ASG activities, CloudWatch alarms |
| stuck lock | предыдущий run прервался | проверь lock и runbook перед force-unlock |

`Terraform init` спрашивает bucket. Возможная причина:

```text
backend.hcl отсутствует
backend.hcl не передан через -backend-config
bucket placeholder не заменён
CI не сгенерировал backend.hcl
```
Что делать:

```bash
ls -la backend.hcl
cat backend.hcl
terraform init -backend-config=backend.hcl -reconfigure
```

Plan role падает. Возможная причина:

```text
TF_PLAN_ROLE_ARN_* не задан
OIDC trust не совпадает с repo/ref/environment
role не даёт доступ к state bucket
role не даёт read/list/describe actions
```

Policy проходит, но risk `BLOCKED`. Возможная причина:

```text
policy outputs missing
cost outputs missing
promotion evidence missing
promotion evidence invalid
incident mode без incident record
```

Смотреть:

```text
risk-decision.md
risk-decision.json
Reason Codes
```

Apply blocked by approval. Проверь:

```text
environment name terraform-dev/stage/prod
required reviewers
prevent self-review
deployment branches
secrets TF_APPLY_ROLE_ARN_*
```

Post-apply exit code `2`. Возможная причина:

```text
drift
eventual consistency
provider read-after-write issue
failed partial apply
resource changed outside Terraform
config не совпадает с applied plan context
```

---

## 14. Практические упражнения

### Упражнение 1. Локальные capstone checks

Запусти:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/run-local-checks.sh
```

Ожидаемо: script и policy checks проходят.

### Упражнение 2. Review package для dev

Создай для `dev`: `tfplan`, `tfplan.txt`, `tfplan.json`, policy outputs, cost outputs, risk decision и reviewer note.

```bash
cd lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive ../..
terraform validate
terraform plan -out=tfplan
terraform show -no-color tfplan > tfplan.txt
terraform show -json tfplan > tfplan.json
sha256sum tfplan > tfplan.sha256
```

Дальше из корня:

```bash
OUT_DIR=/tmp/l76-policy \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/security-policy.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev/tfplan.json
```

```bash
OUT_DIR=/tmp/l76-cost \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/cost-policy.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev/tfplan.json \
  dev
```

```bash
POLICY_DIR=/tmp/l76-policy \
COST_DIR=/tmp/l76-cost \
OUT_DIR=/tmp/l76-risk \
REQUIRE_PROMOTION_EVIDENCE=false \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/risk-classifier.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/dev/tfplan.json \
  dev
```

Ожидаемо: ревьюер может ответить, что изменится и почему `apply` разрешён или заблокирован.

### Упражнение 3. Promotion evidence для stage

Сгенерируй promotion evidence из `dev` в `stage`, затем запусти risk classifier для managed change в `stage`.

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/promotion-evidence-template.sh \
  l76-demo \
  dev \
  "$(git rev-parse HEAD)" \
  "https://github.com/OWNER/REPO/actions/runs/123456789" \
  > /tmp/promotion-evidence-stage.json
```

Проверить:
```bash
jq . /tmp/promotion-evidence-stage.json
```

```bash
POLICY_DIR=/tmp/l76-policy \
COST_DIR=/tmp/l76-cost \
OUT_DIR=/tmp/l76-risk-stage \
PROMOTION_EVIDENCE_FILE=/tmp/promotion-evidence-stage.json \
SOURCE_ENV=dev \
RELEASE_ID=l76-demo \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/risk-classifier.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/lab_76/terraform/envs/stage/tfplan.json \
  stage
```

Ожидаемо: без evidence risk `BLOCKED`; с valid evidence risk зависит от типа change.

### Упражнение 4. High-risk review для prod

Запусти risk classifier для `prod` с promotion evidence из `stage`.

Ожидаемо: для managed changes risk минимум `HIGH`.

### Упражнение 5. Blocked change

Используй fixture, например `public-ingress-plan.json`.

```bash
set +e
OUT_DIR=/tmp/l76-blocked-policy \
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/security-policy.sh \
  lessons/76-capstone-end-to-end-terraform-delivery-pipeline/policies/tests/public-ingress-plan.json
echo "policy exit code=$?"
set -e
```

Ожидаемо: security policy делает `deny`, а risk classifier возвращает `BLOCKED`.

### Упражнение 6. Incident mode

Запусти risk classifier с `INCIDENT_MODE=true` и настоящим `INCIDENT_RECORD_FILE`.

`INCIDENT_MODE` не отключает `security-policy.sh` и `cost-policy.sh`.

Он только говорит `risk-classifier`:

```
это emergency path
promotion evidence можно не требовать
но нужен incident record
```

Ожидаемо: с record risk может быть `EMERGENCY`; без record будет `BLOCKED`.

---

## 15. Пакет доказательств

Используй `proof-pack.en.md` или `proof-pack.ru.md`. Доказательства можно собрать в одну папку и сгенерировать summary:

```bash
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/collect-capstone-proof.sh dev
lessons/76-capstone-end-to-end-terraform-delivery-pipeline/scripts/summarize-capstone.sh <evidence-dir>
```

`collect-capstone-proof.sh` собирает только заранее известные файлы из папок урока, env и evidence. Он не ищет outputs в `/tmp`. Если ты запускал policy/cost/risk scripts с `OUT_DIR=/tmp/...`, сначала скопируй эти директории в папку доказательств.

Минимальные доказательства:

```text
local-checks.txt
tfplan.txt
tfplan.json
policy-decision.txt
cost-decision.txt
risk-decision.md
reviewer-note.md
apply.txt
post_apply_plan.txt
post_apply_exitcode.txt
runtime-health-summary.txt
promotion-manifest.json
capstone-review-summary.md
```

Не коммить сырые доказательства, если там есть account IDs, ARNs, внутренние DNS names, IP-адреса или secrets.

---

## 16. Критерии успеха

Урок завершён, если:

- local checks проходят;
- module tests проходят;
- `dev/stage/prod` roots валидируются;
- PR check template существует;
- promotion template документирует plan-before-approval и exact-plan apply;
- drift check template существует и read-only;
- proof collection и summary scripts работают;
- policy, cost и risk gates работают;
- runtime health script указывает на `lab_76` и собирает evidence;
- proof-pack описывает, что сохранить;
- runbooks связаны с уроком;

---

## 17. Итоги урока

- **Что изучил:** как связать контролы доставки Terraform в один auditable pipeline.
- **Что практиковал:** checks, plans, policies, risk classification, approval, exact-plan apply и verification.
- **Операционный фокус:** применять только то, что было проверено, сохранять evidence и держать recovery runbooks рядом.
- **Почему это важно:** production delivery строится на контролируемых доказательствах и безопасных rollback/recovery paths.
