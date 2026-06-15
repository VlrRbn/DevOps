# Урок 71. Multi-Environment Promotion: dev -> stage -> prod

**Дата:** 2026-06-08

**Фокус:** продвигать один Terraform module contract через несколько окружений без ручного копирования и расхождения конфигураций.

**Главная идея:** окружения — это отдельные развёртывания одного контракта, а не три вручную отредактированные кодовые базы.

---

## Зачем нужен этот урок

В уроках 68-70 был собран контролируемый путь доставки Terraform для одного окружения:

```text
controlled apply -> least-privilege IAM -> JSON plan policy
```

Урок 71 добавляет модель для нескольких окружений:

```text
dev -> stage -> prod
```

Что нельзя делать

Плохая модель:

- скопировал dev
- переименовал руками в stage
- потом ещё раз скопировал в prod
- где-то поправил CIDR
- где-то поправил desired_capacity
- где-то забыл поправить IAM
- где-то поменял module

Через пару недель это уже не три окружения, а три разные инфраструктуры, которые похожи.

Цель не в том, чтобы скопировать Terraform три раза. Цель такая:

- один общий module
- три root-модуля, которые вызывают этот module
- три отдельных state key
- три уровня подтверждения
- одна модель policy
- доказательства на каждом шаге promotion

---

## Что должно получиться

После урока должен уметь:

- разделять Terraform-лабораторную работу на root-модули `dev`, `stage`, `prod`
- держать один общий `modules/network`
- использовать отдельный backend key для каждого окружения
- менять поведение через входные параметры, не редактируя внутренности module
- понимать, почему GitHub OIDC provider - общий объект уровня AWS account
- соблюдать одинаковую дисциплину: plan/policy/apply для каждого окружения
- собирать доказательства для `dev -> stage` и `stage -> prod`

---

## Структура репозитория

```text
lessons/71-multi-environment-promotion/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── lesson71-terraform-promote.yml
├── policies/
│   ├── terraform-plan-policy.sh
│   ├── test-policy.sh
│   └── test-opa.sh
└── lab_71/
    ├── packer/
    └── terraform/
        ├── envs/
        │   ├── dev/
        │   ├── stage/
        │   └── prod/
        └── modules/network/
```

---

## A) Модель окружений

У каждого окружения есть своя root-директория:

```text
lab_71/terraform/envs/dev
lab_71/terraform/envs/stage
lab_71/terraform/envs/prod
```

У каждого root-модуля одинаковая структура:

- `main.tf`
- `variables.tf`
- `outputs.tf`
- `versions.tf`
- `backend.hcl.example`
- `terraform.tfvars.example`

Каждое окружение вызывает один и тот же `modules/network`:

```hcl
module "network" {
  source = "../../modules/network"
}
```

Но передаёт разные значения:

```text
dev   -> маленький размер, low criticality
stage -> ближе к prod, medium criticality
prod  -> строже, high criticality
```

Ключевая мысль:

`dev`, `stage`, `prod` - это не три копии кода. Это три разных вызова одного контракта.

Контракт - это `interface module`:

```text
variables
outputs
validation
preconditions
IAM expectations
state expectations
```

Правило:

```text
Если нужно поменять поведение окружения, сначала меняешь входные параметры root-модуля.

Если нужно поменять сам contract, тогда меняешь общий module, и изменение проходит через:

dev -> stage -> prod
```

Почему это важно:

Представь что меняешь ASG rolling update strategy.

Плохой вариант:

```text
в dev поменял asg.tf
в stage забыл
в prod скопировал старую версию
```

Правильный вариант:

```text
изменил modules/network/asg.tf один раз
проверил в dev
потом тем же commit продвинул в stage
потом тем же commit продвинул в prod
```

Так ты знаешь: `prod` получил именно то изменение, которое уже прошло `dev` и `stage`.

`Promotion` - это доказуемое движение одного release candidate:

```text
same code
same commit
same release_id
same module contract
separate env inputs
stronger approvals near prod
```

---

## B) Изоляция state

У каждого окружения должен быть уникальный state key:

```text
lab71/dev/full/terraform.tfstate
lab71/stage/full/terraform.tfstate
lab71/prod/full/terraform.tfstate
```

Один S3 bucket использовать можно. Один и тот же state key использовать нельзя.

Почему?

`Terraform state` - это карта владения ресурсами.

Он хранит примерно такую информацию:

```text
aws_vpc.main -> vpc-...
aws_subnet.public["a"] -> subnet-...
aws_autoscaling_group.web -> lab71-dev-web-asg
```

Если `dev` и `prod` случайно смотрят в один `state`, Terraform начинает думать, что они управляют одними и теми же ресурсами.

Что может случиться:

- запускаешь `dev apply`
- Terraform читает `prod state`
- видит `prod ресурсы`
- пытается привести их к `dev inputs`


В этом уроке используются явные директории, а не `Terraform CLI workspaces`, потому что так понятнее для CI и проверки изменений.

Когда reviewer смотрит `PR` или `artifact`, он сразу видит:

```text
target_env=stage
backend_key=lab71/stage/full/terraform.tfstate
GitHub Environment=terraform-stage
```

В root variables теперь есть `validation`:

```hcl
variable "environment" {
  validation {
    condition = var.environment == "stage"
  }
}

variable "tf_state_key" {
  validation {
    condition = var.tf_state_key == "lab71/stage/full/terraform.tfstate"
  }
}
```

Это защищает от ручной ошибки.

Зачем две проверки:

- `backend.hcl` нужен самому Terraform backend `key = "lab71/stage/full/terraform.tfstate"`
- а `tf_state_key` внутри variables нужен IAM policy `tf_state_key = "lab71/stage/full/terraform.tfstate"`
- потому что `plan/apply role` должны иметь доступ только к своему state object и lockfile:
- если `backend key` и `IAM policy key` расходятся, будут странные ошибки

---

## C) Входные параметры окружений

Источник module одинаковый.

Общий `module`:

```text
lab_71/terraform/modules/network
```

Отличаются только входные параметры.

```text
lab_71/terraform/envs/dev
lab_71/terraform/envs/stage
lab_71/terraform/envs/prod
```

| Окружение | Project | CIDR | Размер | GitHub Environment |
| --- | --- | --- | --- | --- |
| dev | `lab71-dev` | `10.71.0.0/16` | 1-2 инстанса | `terraform-dev` |
| stage | `lab71-stage` | `10.72.0.0/16` | 2-3 инстанса | `terraform-stage` |
| prod | `lab71-prod` | `10.73.0.0/16` | 2-4 инстанса | `terraform-prod` |

Смысл `dev`: дешевле, меньше инстансов, ниже критичность, проще approval, можно быстрее проверять изменения

Смысл `stage`: ближе к `prod`, проверяет поведение с несколькими инстансами, нужен reviewer, ловит проблемы до `prod`

Смысл `prod`: строже, больше `blast radius`, сильнее approval, меньше debug-доступа

Примеры находятся здесь:

```text
envs/dev/terraform.tfvars.example
envs/stage/terraform.tfvars.example
envs/prod/terraform.tfvars.example
```

Реальные значения должны лежать в игнорируемых локальных tfvars или в CI variables, а не в commit.

---

## D) Ловушка общего OIDC provider

GitHub OIDC provider - объект уровня AWS account.

Не надо создавать его отдельно в state окружений `dev`, `stage`, `prod`. Второе окружение может упасть, потому что provider URL уже существует в AWS account.

AWS скажет примерно: `EntityAlreadyExists`.

Используй это, когда provider уровня account уже создан.

Операционное правило:

```text
Общие объекты уровня account создаются один раз. State отдельных окружений должны получать их по ARN.

github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
```

В `module` это сделано так:

```hcl
resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.github_oidc_provider_arn == "" ? 1 : 0
}
```

- если `ARN` пустой: `создать provider`
- если `ARN` передан: `использовать существующий provider`

`OIDC provider` - это общая дверь из GitHub в AWS account. Если окружения владеют этой дверью, появляется риск:

```text
dev state может случайно удалить общий provider
stage/prod apply roles зависят от объекта, которым владеет dev
владение размыто
```

`Apply policy` больше не разрешает:

```text
iam:CreateOpenIDConnectProvider
iam:DeleteOpenIDConnectProvider
iam:TagOpenIDConnectProvider
```

Apply-роли окружений не должны создавать или удалять общий GitHub OIDC provider. В этой лабораторной работе apply policy управляет ролями и instance profiles конкретного окружения, а общий OIDC provider относится к bootstrap/account setup.

---

## D1) Операционные заметки из этой лабы

В этой лабораторной работе были два полезных сбоя. Их стоит оставить в уроке, потому что они похожи на реальные боевые проблемы.

### 1. Пустой или неправильный `github_oidc_provider_arn`

Симптом:

```text
EntityAlreadyExists: Provider with url https://token.actions.githubusercontent.com already exists
```

Причина:

- GitHub OIDC provider уже существует в AWS account.
- В окружении `github_oidc_provider_arn` пустой или неправильный.
- Terraform видит `count = 1` и пытается создать provider ещё раз.

Правильное исправление:

```hcl
github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
```

Если provider уже попал в state одного окружения, но теперь должен быть общим bootstrap-объектом, его можно убрать из state без удаления из AWS:

```bash
terraform state rm 'module.network.aws_iam_openid_connect_provider.github_actions[0]'
```

Это не удаляет provider в AWS. Это только говорит текущему state: “этот общий объект больше не принадлежит этому окружению”.

### 2. Policy gate упал из-за отсутствующих тегов

Симптом:

```text
POLICY_DECISION=DENY
rule=deny_missing_required_tags
```

Причина:

- Policy из урока 70 проверяет обязательные теги.
- Некоторые ресурсы создавались без `local.tags`.
- Для promotion это правильно: если политика требует теги, модуль должен стабильно ставить их на ресурсы, которые поддерживают теги.

Исправление:

- добавить `tags = merge(local.tags, {...})` на ресурсы, которые поддерживают теги;
- не пытаться “обойти” policy через файл исключений;
- оставить исключения только для заранее согласованных destructive changes.

Вывод:

```text
Policy failure - это не всегда проблема policy.
Часто это сигнал, что module contract не выполняет требования governance.
```

---

## E) Bootstrap / первый запуск

CI workflow для promotion требует IAM role ARNs до того, как сможет выполнить plan или apply:

- `TF_PLAN_ROLE_ARN_DEV`
- `TF_PLAN_ROLE_ARN_STAGE`
- `TF_PLAN_ROLE_ARN_PROD`
- `TF_APPLY_ROLE_ARN_DEV`
- `TF_APPLY_ROLE_ARN_STAGE`
- `TF_APPLY_ROLE_ARN_PROD`

Эти ARN не могут появиться из workflow, у которого ещё нет credentials.

Допустимые варианты первого запуска:

1. Локальный/admin bootstrap: один раз применить первое окружение через admin profile, потом перенести outputs в GitHub variables/environments.
2. Отдельный account bootstrap stack: создать GitHub OIDC и CI roles вне state окружений, потом передавать `github_oidc_provider_arn` в каждое окружение.

В реальном проекте CI roles и OIDC provider лучше вынести в отдельный bootstrap/account stack.

Но сейчас делаем вариант 1: Локальный/admin bootstrap

Для каждого окружения:

```text
cd lessons/71-multi-environment-promotion/lab_71/terraform/envs/dev
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

Заполняешь реальные значения:

```text
web_ami_id = "ami-..."
ssm_proxy_ami_id = "ami-..."
github_owner = "VlrRbn"
github_repo = "DevOps"
github_oidc_provider_arn = "arn:aws:iam::...:oidc-provider/token.actions.githubusercontent.com"
tf_state_bucket_name = "..."
```

Потом:

```text
terraform init -reconfigure -backend-config=backend.hcl
terraform apply

terraform output tf_plan_role_arn
terraform output tf_apply_role_arn
```

Соответствие outputs и GitHub variables:

| Environment | AWS IAM role name | Output | GitHub variable |
| --- | --- | --- | --- |
| `dev` | `lab71-dev-github-actions-plan-role` | `tf_plan_role_arn` | `TF_PLAN_ROLE_ARN_DEV` |
| `stage` | `lab71-stage-github-actions-plan-role` | `tf_plan_role_arn` | `TF_PLAN_ROLE_ARN_STAGE` |
| `prod` | `lab71-prod-github-actions-plan-role` | `tf_plan_role_arn` | `TF_PLAN_ROLE_ARN_PROD` |
| `dev` | `lab71-dev-github-actions-apply-role` | `tf_apply_role_arn` | `TF_APPLY_ROLE_ARN_DEV` |
| `stage` | `lab71-stage-github-actions-apply-role` | `tf_apply_role_arn` | `TF_APPLY_ROLE_ARN_STAGE` |
| `prod` | `lab71-prod-github-actions-apply-role` | `tf_apply_role_arn` | `TF_APPLY_ROLE_ARN_PROD` |

---

## F) Локальная проверка

Из корня репозитория:

```bash
terraform fmt -check -recursive lessons/71-multi-environment-promotion/lab_71/terraform
packer fmt -check -recursive lessons/71-multi-environment-promotion/lab_71/packer
lessons/71-multi-environment-promotion/policies/test-policy.sh
lessons/71-multi-environment-promotion/policies/test-opa.sh
```

Что это проверяет:

- Terraform файлы отформатированы
- Packer HCL файлы отформатированы
- `policy tests` прошли
- `OPA policy tests` прошли

Проверяем, что `root-модуль` и `module interface` сходятся :

```bash
for env in dev stage prod; do
  TF_DATA_DIR="/tmp/l71-${env}-data" \
  terraform -chdir="lessons/71-multi-environment-promotion/lab_71/terraform/envs/${env}" \
    init -backend=false -input=false -no-color

  TF_DATA_DIR="/tmp/l71-${env}-data" \
  terraform -chdir="lessons/71-multi-environment-promotion/lab_71/terraform/envs/${env}" \
    validate -no-color
done
```

Тесты контракта module:

```bash
TF_DATA_DIR=/tmp/l71-module-test-data \
terraform -chdir=lessons/71-multi-environment-promotion/lab_71/terraform/modules/network \
  init -backend=false -input=false -no-color

TF_DATA_DIR=/tmp/l71-module-test-data \
terraform -chdir=lessons/71-multi-environment-promotion/lab_71/terraform/modules/network \
  test -no-color
```

Эти tests проверяют контракт module:

```text
плохой AMI ID падает
один private subnet падает
плохой state key падает
empty tag value падает
reserved tag override падает
outputs остаются стабильными
IAM policy не получает широкие permissions
PassRole ограничен EC2 runtime role
```

---

## G) Workflow продвижения

Шаблон workflow лежит здесь:

```text
ci/lesson71-terraform-promote.yml
```

Когда он готов к запуску, его копируют в:

```text
.github/workflows/lesson71-terraform-promote.yml
```

### Входные параметры workflow

- `target_env`: куда применяем изменение: `dev`, `stage` или `prod`.
- `source_env`: откуда продвигаем изменение: `none`, `dev` или `stage`.
- `release_id`: стабильный идентификатор релиза или change request.
- `source_workflow_run_url`: обязателен для `stage` и `prod`.
- `source_commit_sha`: обязателен для `stage` и `prod`; должен совпадать с текущим commit.
- `allow_destroy_exception_path`: необязательный путь от корня репозитория к JSON-файлу исключений для согласованных destructive changes.
- `confirm_apply`: должен быть ровно `APPLY`.

Разрешены только такие переходы:

```text
none  -> dev
dev   -> stage
stage -> prod
```

Нельзя делать:

```text
none  -> prod
dev   -> prod
stage -> dev
```

Один `release_id` должен проходить всю цепочку:

```text
dev   release_id=rel-l71-001
stage release_id=rel-l71-001
prod  release_id=rel-l71-001
```

Для `dev` предыдущий run не нужен:

```text
source_env=none
```

Для `stage` нужен URL успешного dev run:

```text
source_workflow_run_url=https://github.com/.../actions/runs/123
```

Для `prod` нужен URL успешного stage run.

`source_commit_sha` нужен для `stage` и `prod`, чтобы доказать простую вещь:

```text
stage/prod продвигают тот же код, который уже прошёл предыдущее окружение
```

Если commit другой, workflow падает.

Apply не стартует сразу после plan. Между ними стоит GitHub Environment approval.

Это защита от случайного запуска и от применения плана, который никто не посмотрел.

### Guard step

Сначала workflow проверяет:

```text
confirm_apply == APPLY
release_id не пустой
branch == main
target_env валидный
source_env валидный
promotion path валидный
stage/prod имеют source URL и source SHA
source SHA == current GITHUB_SHA
```

Если что-то не так, workflow падает до получения AWS credentials.

Это важно:

```text
невалидный запрос не должен даже получать AWS OIDC credentials
```

### Проверка предыдущего promotion

Для `stage` и `prod` workflow проверяет предыдущий run через GitHub API.

Он проверяет:

```text
URL указывает на этот же репозиторий
run completed + success
workflow name == lesson71-terraform-promote
head_sha == source_commit_sha
head_sha == current GITHUB_SHA
artifact lesson71-<source_env>-apply существует и не expired
```

Потом скачивает artifact:

```text
lesson71-dev-apply
```

или:

```text
lesson71-stage-apply
```

Внутри должен быть:

```text
promotion-manifest.json
```

Manifest должен содержать:

```text
same release_id
target_env == source_env
commit_sha == current GITHUB_SHA
policy_decision == ALLOW
tfplan_sha256 not empty
workflow_run_url == source_workflow_run_url
```

Без manifest можно случайно взять “какой-то успешный dev run”.

С manifest workflow доказывает:

```text
это тот же release
это тот же commit
это предыдущее окружение
policy была ALLOW
artifact относится к URL, который ввёл оператор
```

### Plan job

После guard и проверки предыдущего run workflow делает:

```text
terraform fmt
terraform test
select plan role
configure AWS credentials via OIDC
write backend.hcl
write terraform.auto.tfvars
terraform init
terraform validate
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
policy check
upload plan artifact
```

Plan role выбирается по окружению:

```text
dev   -> TF_PLAN_ROLE_ARN_DEV
stage -> TF_PLAN_ROLE_ARN_STAGE
prod  -> TF_PLAN_ROLE_ARN_PROD
```

### Apply job

Apply job зависит от plan:

```yaml
needs: plan
```

И привязан к GitHub Environment:

```yaml
environment:
  name: terraform-${{ github.event.inputs.target_env }}
```

То есть:

```text
target_env=prod -> GitHub Environment terraform-prod
```

Там GitHub ждёт approval.

После approval workflow делает:

```text
select TF_APPLY_ROLE_ARN_DEV/STAGE/PROD by target_env
configure AWS credentials via selected apply role ARN
download exact plan artifact
terraform init
terraform apply tfplan
post-apply drift check
write apply-metadata.json
write promotion-manifest.json
upload apply artifact
```

### Почему нужен exact saved plan

Apply использует:

```bash
terraform apply tfplan
```

А не:

```bash
terraform apply
```

Плохой вариант:

```text
plan показал одно
approval дали
apply пересоздал новый plan
применил уже другое
```

Правильный вариант:

```text
reviewer смотрел tfplan
approval дали на tfplan
apply применил именно tfplan
```

### Artifacts

Plan artifact:

```text
lesson71-<env>-plan
```

Содержит:

```text
tfplan
tfplan.txt
tfplan.json
plan.txt
terraform.auto.tfvars
policy-results/
```

Apply artifact:

```text
lesson71-<env>-apply
```

Содержит:

```text
apply.txt
apply-metadata.json
post_apply_plan.txt
post_apply_exitcode.txt
promotion-manifest.json
```

`apply-metadata.json` пишется сразу после apply с `if: always()`.

Смысл:

```text
даже если drift check потом упадёт, останутся metadata по apply attempt
```

`promotion-manifest.json` пишется только после успешного post-apply drift check.

Смысл:

```text
только чистое окружение можно продвигать дальше
```

Если drift check упал, manifest не будет создан. Значит, `stage` или `prod` не смогут использовать этот run как источник promotion.

### Короткий порядок workflow

1. Проверить inputs, branch, release id и путь promotion.
2. Разрешить только `none -> dev`, `dev -> stage`, `stage -> prod`.
3. Для `stage/prod` проверить предыдущий GitHub Actions run через GitHub API.
4. Запустить Terraform fmt.
5. Запустить native module tests.
6. Выбрать plan role для конкретного окружения.
7. Сгенерировать backend и tfvars для выбранного окружения.
8. Выполнить init/validate.
9. Создать saved plan.
10. Конвертировать plan в JSON.
11. Запустить policy gate из урока 70.
12. Загрузить plan artifacts и записать GitHub Step Summary.
13. Дождаться GitHub Environment approval.
14. Получить apply role для окружения.
15. Применить exact saved plan.
16. Запустить post-apply drift check.

Для `stage` и `prod` предыдущий run должен быть успешным завершённым запуском workflow `lesson71-terraform-promote` из того же репозитория, на том же commit, с неистёкшим artifact `lesson71-<source_env>-apply`.

Внутри artifact должен быть `promotion-manifest.json` с тем же `release_id`, тем же commit, `policy_decision=ALLOW` и тем же `workflow_run_url`, который передан в `source_workflow_run_url`.

---

## H) GitHub variables и environments

Repository variables:

- `AWS_REGION`
- `TF_STATE_BUCKET`
- `TF_PLAN_ROLE_ARN_DEV`
- `TF_PLAN_ROLE_ARN_STAGE`
- `TF_PLAN_ROLE_ARN_PROD`
- `TF_APPLY_ROLE_ARN_DEV`
- `TF_APPLY_ROLE_ARN_STAGE`
- `TF_APPLY_ROLE_ARN_PROD`
- `TF_WEB_AMI_ID`
- `TF_SSM_PROXY_AMI_ID`
- `TF_GITHUB_OWNER`
- `TF_GITHUB_REPO`
- `TF_GITHUB_OIDC_PROVIDER_ARN`

GitHub Environments:

- `terraform-dev`
- `terraform-stage`
- `terraform-prod`

GitHub Environments в этом workflow используются как approval gates. Role ARNs хранятся в repository variables с явным env suffix.

Рекомендуемая защита:

| Environment | Protection |
| --- | --- |
| `terraform-dev` | лёгкое подтверждение |
| `terraform-stage` | обязательный reviewer |
| `terraform-prod` | обязательный reviewer + ограничение ветки + optional wait timer |

---

## I) Правила promotion

1. Dev запускается первым: `source_env=none`, `target_env=dev`.

Главная модель: none -> dev -> stage -> prod
После успешного dev workflow должны появиться artifacts:

- lesson71-dev-plan
- lesson71-dev-apply

В lesson71-dev-apply должны быть:

- apply.txt
- apply-metadata.json
- post_apply_plan.txt
- post_apply_exitcode.txt
- promotion-manifest.json - главный документ, который позволит stage проверить dev.

2. Stage запускается только после dev: `source_env=dev`, `target_env=stage`.

Workflow проверяет:

- source_workflow_run_url указывает на этот repository
- source run завершился success
- source run был workflow lesson71-terraform-promote
- source run был на том же commit
- source artifact lesson71-dev-apply существует
- artifact не expired
- в artifact есть promotion-manifest.json
- manifest.release_id == текущий release_id
- manifest.target_env == dev
- manifest.commit_sha == текущий commit
- manifest.policy_decision == ALLOW
- manifest.workflow_run_url == source_workflow_run_url

3. Prod запускается только после stage: `source_env=stage`, `target_env=prod`.
4. Module source одинаковый во всех окружениях.
5. Один и тот же AMI/build продвигается как release candidate.
6. State key всегда разные.
7. Plan role разделена по окружениям.
8. Prod требует более строгого approval.
9. Apply использует exact saved plan artifact.
10. У каждого promotion есть доказательства: release id, URL предыдущего run, source commit, policy decision, artifacts.

Заметка про provider lock: в этом учебном repository `.terraform.lock.hcl` игнорируется для временных root-модулей уроков. В production lock files обычно коммитят отдельно для каждого root module.

Почему:

- CI и локальный запуск используют одинаковые provider versions
- меньше неожиданных изменений от provider upgrade
- promotion воспроизводимее

Promotion - это “один contract, контролируемые входные параметры, более строгие проверки по мере движения к prod”.

---

## J) Упражнения и проверки

### Проверка 1. Доказать изоляцию root-модулей

Проверь backend examples (или просто backend):

```bash
for env in dev stage prod; do
  echo "--- $env"
  cat lessons/71-multi-environment-promotion/lab_71/terraform/envs/$env/backend.hcl.example
  grep "lab71/${env}/full/terraform.tfstate" \
    lessons/71-multi-environment-promotion/lab_71/terraform/envs/$env/backend.hcl.example
done
```

Что она доказывает:

```bash
dev backend example содержит lab71/dev/full/terraform.tfstate
stage backend example содержит lab71/stage/full/terraform.tfstate
prod backend example содержит lab71/prod/full/terraform.tfstate
```

### Проверка 2. Проверить все root-модули

Проверяем все окружения без подключения к remote backend.

```bash
for env in dev stage prod; do
  TF_DATA_DIR="/tmp/l71-${env}-data" terraform \
    -chdir="lessons/71-multi-environment-promotion/lab_71/terraform/envs/${env}" \
    init -backend=false -input=false -no-color

  TF_DATA_DIR="/tmp/l71-${env}-data" terraform \
    -chdir="lessons/71-multi-environment-promotion/lab_71/terraform/envs/${env}" \
    validate -no-color
done
```

### Проверка 3. Доказать общий module source

```bash
for env in dev stage prod; do
  grep 'source = "../../modules/network"' \
    lessons/71-multi-environment-promotion/lab_71/terraform/envs/$env/main.tf
done
```

### Проверка 4. Доказать разные входные параметры

```bash
for env in dev stage prod; do
  echo "--- $env"
  grep -E 'project_name|environment|vpc_cidr|tf_state_key|github_apply_environment' \
    lessons/71-multi-environment-promotion/lab_71/terraform/envs/$env/terraform.tfvars.example
done
```

### Проверка 5. Запустить policy tests

```bash
lessons/71-multi-environment-promotion/policies/test-policy.sh
lessons/71-multi-environment-promotion/policies/test-opa.sh
```

### Упражнение 1. Успешная цепочка promotion

Пройди полный успешный сценарий в GitHub Actions:

1. Dev:

```text
target_env=dev
source_env=none
release_id=rel-l71-001
confirm_apply=APPLY
```

Сохрани `lesson71-dev-plan`, `lesson71-dev-apply`, `apply-metadata.json` и `promotion-manifest.json`.

2. Stage:

```text
target_env=stage
source_env=dev
release_id=rel-l71-001
source_workflow_run_url=<dev workflow run URL>
source_commit_sha=<dev commit SHA>
confirm_apply=APPLY
```

Сохрани `lesson71-stage-plan`, `lesson71-stage-apply`, `apply-metadata.json` и `promotion-manifest.json`.

3. Prod:

```text
target_env=prod
source_env=stage
release_id=rel-l71-001
source_workflow_run_url=<stage workflow run URL>
source_commit_sha=<stage commit SHA>
confirm_apply=APPLY
```

Сохрани prod artifacts, `apply-metadata.json`, `promotion-manifest.json` и заполни `proof-pack.en.md` или `proof-pack.ru.md`.

### Упражнение 2. Отклонить prod-first promotion

В GitHub Actions запусти workflow с такими inputs:

```text
target_env=prod
source_env=none
release_id=rel-test-prod-first
confirm_apply=APPLY
```

Ожидаемый результат: guard step падает до получения AWS credentials.

### Упражнение 3. Отклонить promotion с неправильным commit

Запусти workflow с такими входными параметрами:

```text
target_env=stage
source_env=dev
release_id=rel-test-wrong-sha
source_workflow_run_url=<previous dev run URL>
source_commit_sha=0000000000000000000000000000000000000000
confirm_apply=APPLY
```

Ожидаемый результат: guard step отклоняет promotion, потому что source commit не совпадает с текущим commit workflow.

---

## Пакет доказательств

Используй:

```text
proof-pack.en.md
proof-pack.ru.md
```

Минимум доказательств:

- матрица окружений
- доказательство backend key
- plan artifact для окружения
- policy decision для окружения
- доказательство approval для окружения
- результат post-apply drift для окружения
- `apply-metadata.json` и `promotion-manifest.json`
- запись решения о promotion

---

## Частые ошибки

- Использовать один state key для нескольких окружений.
- Редактировать код module отдельно под env.
- Создавать один и тот же GitHub OIDC provider в нескольких state.
- Подтверждать prod до появления plan/policy artifacts.
- Считать stage необязательным.
- Запускать prod первым.
- Разводить workflow input, backend key и GitHub Environment в разные стороны.

---

## Критерии успеха

Урок закрыт, когда:

- `envs/dev`, `envs/stage`, `envs/prod` проходят validate
- module tests проходят
- policy tests проходят
- CI template консистентно связывает target env, директорию, state key и GitHub Environment
- proof-pack объясняет, какие доказательства сохранять
- можешь объяснить ловушку общего GitHub OIDC provider

---

## Итоги урока

- **Что изучил:** promotion - это контролируемое движение через изолированные state окружений.
- **Что практиковал:** env roots, backend keys, env-specific tfvars, выбор target env в CI, повторное использование policy.
- **Операционный навык:** держать module source стабильным, меняя уровень проверок по окружениям.
- **Promotion rule:** dev first, stage second, prod last.
