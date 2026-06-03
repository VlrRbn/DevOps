# Урок 68. Controlled Terraform Apply Pipeline

**Дата:** 2026-06-01

**Фокус:** собрать manual approval-gated Terraform `apply` workflow, который применяет только fresh saved plan из `main`, использует OIDC, remote state locking и сохраняет post-apply evidence.

**Подход:** `plan` это review. `apply` это release.

References:

- GitHub Actions deployments and environments: https://docs.github.com/en/actions/reference/deployments-and-environments
- Terraform saved plan/apply behavior: https://developer.hashicorp.com/terraform/cli/commands/apply
- Terraform plan `-out` behavior: https://developer.hashicorp.com/terraform/cli/commands/plan

---

## Зачем этот урок

Уже собрна одна сторона безопасной Terraform delivery system:

- remote state and locking
- PR plan pipeline
- quality gates
- drift detection
- secret-safe inputs
- module contracts
- native module tests

Остаётся опасный gap:

> Кто может запускать `terraform apply`, из какого source, с каким plan, и как мы доказываем результат?

```text
Кто реально имеет право менять AWS?
Откуда запускается apply?
Какой именно plan применяется?
Кто это одобрил?
Как потом доказать, что apply прошёл чисто?
```

Плохой pattern:

```text
push to main -> terraform apply -auto-approve
```

Почему плохой:

- любой merge может сразу менять AWS;
- человек может не увидеть финальный fresh plan;
- нет нормального approval;
- сложно доказать, что именно применялось;
- destroy/replacement может пройти слишком легко.

Лучший pattern:

```text
PR plan reviewed
  -> merge to main
  -> manual workflow_dispatch
  -> fresh saved plan from main
  -> upload plan artifact
  -> review plan artifact
  -> GitHub Environment approval
  -> apply exact saved plan artifact
  -> post-apply drift check
  -> artifacts and decision note
```

Урок 68 превращает Terraform apply в controlled release step.

---

## Что должен уметь после урока

- объяснить, почему apply требует более строгих controls, чем plan
- создать GitHub Environment gate для Terraform apply
- разделить plan-role и apply-role trust models
- привязать apply role к GitHub Environment OIDC subject
- запускать module native tests до apply
- генерировать fresh saved plan из `main`
- применять именно этот saved plan
- блокировать очевидные destroy/replacement plans без явного понимания
- запускать post-apply drift verification
- собирать operational proof artifacts
- объяснить rollback как ещё один controlled apply

---

## Быстрый маршрут

1. Bootstrap remote state, если он ещё не создан.
2. Один раз применить lab локально или через trusted admin path, чтобы создать GitHub OIDC roles.
3. Скопировать `tf_plan_role_arn` в GitHub repository variable `TF_PLAN_ROLE_ARN`.
4. Скопировать `tf_apply_role_arn` в GitHub repository variable `TF_APPLY_ROLE_ARN`.
5. Создать GitHub Environment `terraform-dev`.
6. Настроить required reviewers для `terraform-dev`.
7. Добавить required repository variables.
8. Использовать `.github/workflows/lesson68-terraform-apply-dev.yml`.
9. Запустить workflow вручную из `main` с `confirm_apply=APPLY`.
10. Проверить plan artifact из `plan-dev`.
11. Approve `terraform-dev` environment deployment для `apply-dev`.
12. Проверить apply artifacts и post-apply result.

---

## Требования

- Урок 60: remote state and native S3 lockfile.
- Урок 63: PR plan pipeline.
- Урок 64: drift detection.
- Урок 67: Terraform native tests.
- Terraform state bucket существует.
- Web и SSM proxy AMI IDs существуют.
- Есть права создать GitHub repository variables.
- Есть права создать или использовать GitHub Environment `terraform-dev`.

---

## Структура

```text
lessons/68-controlled-terraform-apply-pipeline/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── terraform-apply-dev.yml
└── lab_68/
    └── terraform/
        ├── backend-bootstrap/
        ├── envs/
        └── modules/network/
```

Active workflow path:

```text
.github/workflows/lesson68-terraform-apply-dev.yml
```

---

## A) Apply Delivery Model

Controlled apply pipeline имеет пять gates.

| Gate | Purpose |
| --- | --- |
| Source gate | Apply только из `main` |
| Human gate | GitHub Environment approval |
| Identity gate | OIDC apply role, no static keys |
| Plan gate | Fresh saved plan from current `main` |
| Verification gate | Post-apply drift check and evidence |

Правило:

> Не применяй stale PR plan artifact слепо.

PR plan нужен для review. Apply workflow создаёт fresh plan после merge, потому что remote state, cloud reality или `main` могли измениться с момента открытия PR.

Главная модель:

```text
plan = review material
apply = controlled release
```

---

## B) Bootstrap Reality

Есть неизбежная проблема:

> Apply workflow нуждается в AWS apply role, но Terraform сам создаёт эту role.

Значит первый запуск не может быть полностью self-service.

Рекомендуемый lab bootstrap:

1. Создать или переиспользовать remote state bucket.
2. Запустить Terraform локально или через trusted admin path.
3. Создать GitHub OIDC provider и roles.
4. Забрать outputs:
   - `tf_plan_role_arn`
   - `tf_apply_role_arn`
5. Сохранить `tf_apply_role_arn` в GitHub variable `TF_APPLY_ROLE_ARN`.
6. Дальше использовать controlled apply workflow.

CI/CD системы часто требуют bootstrap phase перед тем, как начинают управлять сами собой.

---

## C) GitHub Environment Gate

Создай environment:

```text
terraform-dev
```

Настрой, если доступно:

- required reviewers
- prevent self-review
- deployment branch rule: `main`
- optional wait timer

Почему это важно:

- apply job останавливается до environment approval
- approval виден в GitHub run
- environment-level variables/secrets можно отделить от PR jobs
- AWS role trust можно привязать к environment subject

В этой lab apply role trust policy ожидает OIDC subject:

```text
repo:<owner>/<repo>:environment:terraform-dev
```

Это значит, что обычный PR job не сможет assume apply role, если он не запускается как deployment в approved environment.

---

## D) IAM Role Model

В lab теперь две GitHub Actions roles.

| Role | Output | Trust model | Purpose |
| --- | --- | --- | --- |
| Plan role | `tf_plan_role_arn` | branch/PR subject | read/plan/backend checks |
| Apply role | `tf_apply_role_arn` | environment subject | approved Terraform apply |

Apply role отдельная, потому что apply имеет mutation power.

Lab simplification:

- `github_actions_apply_role` получает `AdministratorAccess`.
- Для focused lab по pipeline controls это допустимо.
- Для реальной системы замени на scoped policy и отдельный break-glass runbook.

Правило:

> More power means narrower trust, stronger approval, and better evidence.

---

## E) Required GitHub Variables

Добавь repository variables:

| Variable | Example | Purpose |
| --- | --- | --- |
| `AWS_REGION` | `eu-west-1` | AWS region |
| `TF_STATE_BUCKET` | `vlrrbn-tfstate-...` | remote backend bucket |
| `TF_PLAN_ROLE_ARN` | `arn:aws:iam::...:role/lab68-github-actions-role` | OIDC plan role |
| `TF_APPLY_ROLE_ARN` | `arn:aws:iam::...:role/lab68-github-actions-apply-role` | OIDC apply role |
| `TF_WEB_AMI_ID` | `ami-...` | web launch template AMI |
| `TF_SSM_PROXY_AMI_ID` | `ami-...` | SSM proxy AMI |

Workflow пишет `backend.hcl` и `terraform.auto.tfvars` во время run. Он не зависит от committed `terraform.tfvars`.

Это важно, потому что `terraform.tfvars` intentionally ignored.

---

## F) Workflow Design

Workflow file:

```text
.github/workflows/lesson68-terraform-apply-dev.yml
```

Template copy:

```text
lessons/68-controlled-terraform-apply-pipeline/ci/terraform-apply-dev.yml
```

Core controls:

- only `workflow_dispatch`
- explicit guard step падает, если `confirm_apply` не равен `APPLY`
- explicit guard step падает, если run не из `main`
- `plan-dev` идёт без GitHub Environment approval
- `plan-dev` запускает fmt и native tests до AWS credentials
- `plan-dev` assumes lower-power plan role
- `plan-dev` создаёт `tfplan`, `tfplan.txt` и `tfplan.json`
- `plan-dev` uploads `lesson68-terraform-plan-dev` для human review
- `apply-dev` ждёт GitHub Environment `terraform-dev` approval
- `apply-dev` assumes environment-scoped apply role
- `apply-dev` downloads и применяет exact saved `tfplan` artifact
- destroy/replacement определяется из JSON plan через `jq`
- post-apply verification запускает `terraform plan -detailed-exitcode`
- оба jobs uploads short-lived operational artifacts

Важное отличие:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Это значит, что apply использует exact saved plan. Он не пересчитывает другой plan silently during apply.

---

## G) Destroy Guard

Workflow использует JSON plan, а не grep по human-readable text:

```bash
terraform show -json tfplan > tfplan.json
jq '[.resource_changes[]? | select(.change.actions | index("delete"))]' tfplan.json
```

Так ловится и прямой destroy, и replacement, потому что Terraform replacement содержит delete action.

Это всё ещё learning guardrail, не полноценный policy engine.

Он блокирует apply, если operator явно не перезапустил run с:

```text
allow_destroy=ALLOW_DESTROY
```

В production добавляй более сильные policy gates:

- OPA/Conftest
- Sentinel
- Checkov policy
- parsed JSON plan checks with allowed action lists
- explicit change windows
- separate break-glass workflow

Lab rule:

> Если destroy/replacement появился, остановись и объясни before applying.

---

## H) Post-Apply Verification

После apply запускается:

```bash
terraform plan -detailed-exitcode
```

Exit codes:

| Code | Meaning | Pipeline action |
| --- | --- | --- |
| `0` | no diff | success |
| `1` | error | fail |
| `2` | diff remains | fail and inspect |

Почему это важно:

- apply может succeed, но оставить residual drift/diff
- provider defaults могут изменить state shape
- external systems могут менять resources during apply
- clean post-apply plan это strong evidence

Это не full runtime smoke test. Это доказывает, что Terraform state and config agree after apply.

---

## I) Artifact Discipline

В уроке есть два artifact:

```text
lesson68-terraform-plan-dev
lesson68-terraform-apply-dev
```

`lesson68-terraform-plan-dev` нужен до approval:

```text
plan.txt                      -> output команды terraform plan
tfplan.txt                    -> saved plan в человекочитаемом виде
tfplan.json                   -> машинная проверка/policy
tfplan                        -> binary plan для apply
destructive_changes.json      -> список ресурсов с delete/replacement
destructive-summary.txt       -> короткий итог destructive_count
```

`lesson68-terraform-apply-dev` нужен после apply:

```text
plan.txt
tfplan.txt
tfplan.json
destructive_changes.json
destructive-summary.txt
apply.txt                      -> что реально произошло при apply
post_apply_plan.txt            -> проверка после apply
post_apply_exitcode.txt        -> 0/1/2 результат проверки
```

Artifacts это operational data.

Они могут содержать:

- resource names
- ARNs
- security group IDs
- subnet IDs
- tags
- AMI IDs
- IAM role names

Retention short: `7` days.

Proof pack должен ответить:

- Какой run?
- Какой commit SHA?
- Кто approve сделал?
- Какой plan был?
- Был ли destroy?
- Что применили?
- Чистый ли post-apply plan?
- Нужен ли rollback?

---

## J) Rollback Model

Этот урок не делает auto rollback.

Rollback это тоже apply.

### Option 1 - Revert commit and apply

Используй, если change был code-based и revert понятный.

```text
git revert <bad commit>
open PR
review plan
merge
manual apply
post-apply verify
```

### Option 2 - Fix forward

Используй, если revert рискованнее, чем маленькое исправление.

Например:

- ресурс уже пересоздан;
- старое состояние не вернуть без риска;
- rollback ломает новую зависимость;
- проще поправить параметр и применить.

### Option 3 - Break-glass runbook

Используй только если:

- CI сломан;
- инфраструктура деградирует;
- delay worse than controlled manual action;
- нужен ручной emergency action.

Break-glass всё равно требует evidence after the fact.

```text
что сделали
кто сделал
когда
почему
как вернули под Terraform control
```

---

## Финальная модель урока

```text
source gate:
  только main

manual gate:
  workflow_dispatch + confirm_apply=APPLY

quality gate:
  fmt + terraform test

identity gate:
  plan role для plan-dev
  apply role для apply-dev
  OIDC без static AWS keys

plan gate:
  fresh terraform plan -out=tfplan из main

review gate:
  plan artifact перед approval

human gate:
  GitHub Environment terraform-dev

safety gate:
  JSON destroy/replacement guard

apply gate:
  terraform apply exact saved tfplan

verification gate:
  post-apply terraform plan -detailed-exitcode

evidence gate:
  artifacts + decision note
```

---

## K) Drills

### Drill 1 - Safe tag apply

Измени harmless tag или alarm description.

Expected:

- PR plan показывает change
- merge to `main`
- manual apply workflow ждёт environment approval
- apply succeeds
- post-apply exit code is `0`

### Drill 2 - Confirm guard

Запусти workflow с:

```text
confirm_apply = NO
```

Expected:

- apply job does not run

### Drill 3 - Environment approval

Запусти workflow с valid inputs.

Expected:

- job pauses at `terraform-dev`
- reviewer approves
- apply continues

### Drill 4 - Destroy guard

Сделай change, который would destroy or replace safe lab resource.

Expected:

- workflow stops before apply unless `allow_destroy=ALLOW_DESTROY`
- artifact shows risky plan

### Drill 5 - Post-apply proof

После apply проверь:

```text
post_apply_exitcode.txt
post_apply_plan.txt
```

Expected:

- exit code `0`
- no residual diff

---

## L) Proof Pack

Capture:

```text
evidence/
  apply-run-url.txt
  environment-approval-note.md
  repository-vars-redacted.md
  plan.txt
  tfplan.txt
  apply.txt
  post_apply_plan.txt
  post_apply_exitcode.txt
  decision.txt
```

`decision.txt` должен отвечать:

```markdown
# Apply Decision

- Source branch:
- Commit SHA:
- Environment:
- Reviewer:
- Expected change:
- Destroy/replacement present: yes/no
- allow_destroy used: yes/no
- Applied saved plan: yes/no
- Post-apply plan clean: yes/no
- Rollback needed: yes/no
```

---

## Частые ошибки

- automatic apply on every push to main too early
- same IAM role for PR plan and apply
- applying stale PR plan artifacts
- relying on ignored local `terraform.tfvars` in CI
- no GitHub Environment approval
- OIDC trust not bound to environment
- canceling an in-progress apply
- treating JSON destroy guard as a complete policy engine
- uploading artifacts without thinking about sensitivity
- skipping post-apply drift check

---

## Security Checklist

- OIDC only, no static AWS keys
- apply role separate from plan role
- apply role bound to GitHub Environment subject
- apply workflow runs only from `main`
- apply workflow is `workflow_dispatch`
- `confirm_apply=APPLY` required
- GitHub Environment approval required
- remote backend uses native S3 lockfile
- saved plan is applied
- destroy/replacement requires explicit acknowledgment
- post-apply drift check required
- artifacts have short retention

---

## Финальные критерии

Урок 68 завершён, если:

- [ ] `terraform-dev` environment exists
- [ ] plan role ARN stored in `TF_PLAN_ROLE_ARN`
- [ ] apply role ARN stored in `TF_APPLY_ROLE_ARN`
- [ ] required GitHub variables configured
- [ ] workflow runs only from `main`
- [ ] environment approval required
- [ ] native tests run before apply
- [ ] saved plan generated and applied
- [ ] destroy guard blocks risky changes by default
- [ ] post-apply plan returns exit code `0`
- [ ] proof pack captured
- [ ] rollback decision documented if needed

---

## Итоги Урока

- **Что изучил:** Terraform apply должен быть controlled release, not generic CI.
- **Что практиковал:** GitHub Environment approval, OIDC apply role, saved plan apply, destroy guard, post-apply drift check.
- **Операционный фокус:** apply only after source, human, identity, plan, and verification gates pass.
- **Почему это важно:** safest plan pipeline всё равно провалится operationally, если apply uncontrolled.
