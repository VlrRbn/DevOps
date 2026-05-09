# lesson_63

---

# Terraform CI Plan Pipeline (OIDC, Remote State, PR-Safe Delivery)

**Date:** 2026-05-09

**Focus:** собрать read-only Terraform PR plan pipeline на GitHub Actions с OIDC, remote state, concurrency control и plan artifacts.

**Mindset:** quality gates говорят, выглядит ли код приемлемо; plan pipeline показывает, что Terraform собирается сделать до merge.

---

## Зачем Этот Урок

Quality gates отвечают на вопросы:

- форматирован ли HCL?
- валидна ли конфигурация?
- нарушает ли она lint/policy baseline?

Но они **не отвечают** на главный вопрос:

> Что этот pull request реально сделает с инфраструктурой?

Это закрывает CI **plan pipeline**.

Terraform PR workflow должен:

- запускаться автоматически на pull request
- аутентифицироваться в AWS без long-lived static keys
- безопасно использовать существующий remote backend
- выпускать читаемый `terraform plan`
- сохранять plan artifacts для review
- никогда не выполнять `apply`

---

## Что Должно Получиться

- собрать GitHub Actions workflow для Terraform plan на PR
- аутентифицироваться в AWS через GitHub OIDC assume-role
- безопасно использовать remote S3 backend из CI
- не допускать конфликтов между параллельными CI runs
- загружать human-readable plan artifact
- сохранять success/failure evidence для review
- понимать, что CI plan это review tool, а не apply tool

---

## Quick Path

1. Определить целевую форму PR workflow.
2. Подготовить AWS IAM role для GitHub OIDC.
3. Ограничить workflow только путями lesson Terraform.
4. Прогнать `fmt`, `validate`, `tflint`, `checkov`, потом `terraform plan`.
6. Добавить concurrency, чтобы оставался только последний PR run.
7. Доказать и success path, и failure path.

---

## Prerequisites

- lesson 60 completed: remote state и locking
- lesson 61 completed: safe refactors и state hygiene
- lesson 62 completed: Terraform quality gates baseline

---

## Структура Урока

```text
lessons/63-terraform-ci-plan-pipeline/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── terraform-plan-pr.yml
└── lab_63/
    ├── packer/
    └── terraform/
        ├── .tflint.hcl
        ├── backend-bootstrap/
        ├── envs/
        └── modules/network/
```

---

## Target Flow

```text
Pull Request
  |
  v
GitHub Actions
  |
  +--> terraform fmt -check
  +--> terraform validate
  +--> tflint
  +--> checkov
  +--> terraform plan
           |
           v
      artifact upload
           |
           v
   reviewer читает plan до merge
```

Критическое правило:

- CI может **plan**
- CI не должен делать `apply`

---

## A) Модель Доставки, Которую Нужно Понять

Terraform delivery-цепочка теперь такая:

1. локальная правка
2. локальные быстрые проверки
3. push branch
4. open PR
5. CI гоняет quality gates
6. CI гоняет read-only Terraform plan
7. reviewer смотрит и код, и plan output
8. merge происходит только после понимания infrastructure impact

---

## B) Модель Аутентификации: OIDC, А Не Static AWS Keys

Не хранить long-lived AWS access keys в GitHub secrets для Terraform CI, если можно этого избежать.

Использовать GitHub Actions OIDC, чтобы job получал short-lived credentials через assume-role.

Плюсы:

- нет long-lived AWS keys в GitHub
- IAM trust можно сузить до конкретного repo
- audit trail в AWS чище
- меньше secret sprawl между окружениями

Обязательные GitHub job permissions:

```yaml
permissions:
  id-token: write
  contents: read
```

Если потом захочешь PR comments, добавь:

```yaml
  pull-requests: write
```

`id-token: write` позволяет GitHub выпустить OIDC token.

---

## C) AWS Side: IAM Role Для GitHub Actions

Создай или переиспользуй IAM role, которую сможет assume GitHub Actions.

### Форма Trust Policy

Нужно разрешить:

- `token.actions.githubusercontent.com` как federated principal
- `aud = sts.amazonaws.com`
- `sub`, ограниченный repo

Пример trust policy:

```json
{
  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"

            # Разрешаем только конкретный repo и конкретную ветку.
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch}"
          }
        }
      }
    ]
  })
}
```

### Форма Прав Для CI Role

Для plan-only pipeline роли обычно нужны:

- backend access для S3 state object и lockfile
- read access к ресурсам, которые Terraform refreshes during plan
- без широких mutate permissions, если они реально не требуются

Практическая мысль:

`terraform plan` не полностью “read-only”. Он всё равно работает с remote backend и refreshes provider state.
Но scope роли всё равно нужно держать узким.

---

## D) Правила Дизайна Workflow

### 1. Триггери только нужные пути

Не гоняй Terraform CI на каждом README change во всём repo.

Нормальный path filter:

```yaml
on:
  pull_request:
    paths:
      - 'lessons/63-terraform-ci-plan-pipeline/lab_63/terraform/**'
      - '.github/workflows/terraform-plan-pr.yml'
```

Подстрой под свой реальный layout.

### 2. Concurrency обязательна

Если ты запушил три раза в один PR, выживать должен только последний run.

```yaml
concurrency:
  group: terraform-plan-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
```

Без этого CI превращается в шум и backend contention.

### 3. Backend config должна быть явной

CI должен знать:

- backend bucket
- state key
- region
- lockfile mode

Нельзя рассчитывать на локальную машину или вручную созданный hidden file.

### 4. CI не должен мигрировать state

Используй:

```bash
terraform init -reconfigure -backend-config=backend.hcl
```

Не используй `-migrate-state` в CI.

Миграция state это operator action, а не pipeline action.

---

## E) Пример Workflow (`ci/terraform-plan-pr.yml`)

В этом уроке сначала держим workflow рядом с lesson. Копировать его в `.github/workflows/` стоит только когда ты уже осознанно готов.

Рекомендуемые repo variables / secrets:

- `vars.AWS_REGION`
- `vars.TF_PLAN_ROLE_ARN`
- `vars.TF_STATE_BUCKET`

Пример:

```yaml
name: terraform-plan-pr

on:
  pull_request:
    paths:
      - 'lessons/63-terraform-ci-plan-pipeline/lab_63/terraform/**'
      - '.github/workflows/terraform-plan-pr.yml'
  workflow_dispatch: {}

permissions:
  id-token: write
  contents: read

concurrency:
  group: terraform-plan-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

env:
  TF_ROOT: lessons/63-terraform-ci-plan-pipeline/lab_63/terraform
  TF_IN_AUTOMATION: true
  TF_INPUT: false
  AWS_REGION: ${{ vars.AWS_REGION || 'eu-west-1' }}

jobs:
  terraform-plan:
    if: ${{ github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository }}
    runs-on: ubuntu-latest

    defaults:
      run:
        shell: bash
        working-directory: ${{ env.TF_ROOT }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: '1.14.0'
          terraform_wrapper: false

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: ${{ env.AWS_REGION }}
          role-to-assume: ${{ vars.TF_PLAN_ROLE_ARN }}
          role-session-name: gha-terraform-plan

      - name: Terraform fmt
        run: terraform fmt -check -recursive

      - name: Terraform init (no backend)
        run: terraform -chdir=envs init -backend=false -input=false -no-color

      - name: Terraform validate
        run: terraform -chdir=envs validate -no-color

      - name: Setup TFLint
        uses: terraform-linters/setup-tflint@v6
        with:
          tflint_version: 'v0.60.0'
          cache: true

      - name: TFLint init
        run: tflint --chdir=envs --config=../.tflint.hcl --init
        env:
          GITHUB_TOKEN: ${{ github.token }}

      - name: TFLint
        run: tflint --chdir=envs --config=../.tflint.hcl -f compact

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install Checkov
        run: pip install checkov==3.2.469

      - name: Checkov
        run: checkov -d . --framework terraform --config-file ../../checkov.yaml

      - name: Write backend.hcl
        working-directory: ${{ env.TF_ROOT }}/envs
        run: |
          cat > backend.hcl <<EOF
          bucket       = "${{ vars.TF_STATE_BUCKET }}"
          key          = "lab63/dev/full/terraform.tfstate"
          region       = "${{ env.AWS_REGION }}"
          encrypt      = true
          use_lockfile = true
          EOF

      - name: Terraform init (remote backend)
        run: terraform -chdir=envs init -reconfigure -backend-config=backend.hcl -input=false -no-color

      - name: Terraform plan
        run: terraform -chdir=envs plan -input=false -no-color -out=tfplan | tee envs/plan.txt

      - name: Terraform show
        run: terraform -chdir=envs show -no-color tfplan > envs/tfplan.txt

      - name: Upload plan artifact
        uses: actions/upload-artifact@v4
        with:
          name: terraform-plan
          path: |
            ${{ env.TF_ROOT }}/envs/tfplan
            ${{ env.TF_ROOT }}/envs/tfplan.txt
            ${{ env.TF_ROOT }}/envs/plan.txt

      - name: Job summary
        run: |
          {
            echo "## Terraform PR Plan"
            echo
            echo "- fmt: passed"
            echo "- validate: passed"
            echo "- tflint: passed"
            echo "- checkov: passed"
            echo "- plan artifact: uploaded"
          } >> "$GITHUB_STEP_SUMMARY"
```

---

## F) Дисциплина Чтения Plan

Для каждого нетривиального PR нужно уметь отвечать на четыре вопроса:

- что добавится?
- что изменится?
- что удалится?
- это ожидаемо или нет?

---

## G) Proof Pack (Обязательные Артефакты)

Сохранить минимум:

- successful PR plan run
- failed validate run
- failed `checkov` или `tflint` run
- evidence, что plan artifact загрузился
- evidence concurrency cancellation
- короткий decision note:
  - что менялось
  - что показал CI
  - почему это полезно до merge

Конкретный шаблон смотри в `proof-pack.ru.md`.

---

## Drills (Обязательные)

### Drill 1: Healthy PR plan

Сделать безопасное и видимое изменение:

- tag change
- изменение alarm description
- comment-safe tweak, который всё равно даёт plan

Ожидаемый результат:

- workflow проходит
- plan artifact существует
- summary читается

### Drill 2: Broken HCL

Внести синтаксическую ошибку или invalid reference.

Ожидаемый результат:

- workflow падает на `validate`
- до `plan` не доходит

### Drill 3: Policy break

Вернуть один footgun из lesson 62:

- убрать IMDSv2 requirement
- открыть public ingress
- ослабить backend protection внутри scope урока

Ожидаемый результат:

- workflow падает на `checkov` и/или `tflint`

### Drill 4: Concurrency proof

Быстро запушить два коммита в один PR.

Ожидаемый результат:

- первый run отменяется
- выживает последний run

---

## Common Pitfalls

- использовать static AWS keys вместо OIDC
- позволять CI делать `apply`
- забыть concurrency guard
- неаккуратно зашить backend config в repo
- сделать path filters слишком широкими или слишком узкими
- думать, что `validate` достаточно и можно пропустить реальный `plan`
- считать plan artifacts шумом, а не review data

---

## Final Acceptance

Lesson 63 закрыт, если:

- [ ] GitHub Actions запускает Terraform plan на PR
- [ ] AWS auth работает через OIDC assume-role
- [ ] remote backend init работает в CI
- [ ] plan artifact загружается
- [ ] плохой код падает до `plan`
- [ ] concurrency cancellation видно в CI
- [ ] можешь объяснить plan до merge

---

## Lesson Summary

- **Что изучил:** как строить безопасный Terraform PR plan pipeline.
- **Что практиковал:** OIDC auth, backend-aware CI, concurrency control, artifact upload, fail-fast delivery.
- **Операционный фокус:** сначала plan до merge, apply потом и отдельно.
- **Почему это важно:** quality gates ловят плохой код, а plan показывает реальный infrastructure impact.
