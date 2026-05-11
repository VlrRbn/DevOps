# lesson_64

---

# Drift Detection & Change Awareness (Scheduled Plan, Evidence, Triage)

**Date:** 2026-05-10

**Focus:** безопасно обнаруживать infrastructure drift и объяснять, что изменилось, где именно, и что делать дальше.

**Mindset:** если Terraform state и реальная инфраструктура расходятся, следующий `apply` становится сюрпризом.

---

## Зачем Этот Урок

После lesson 63 pull request уже показывает, что Terraform **сделает** до merge.

Но остаётся другой риск:

- кто-то поменял AWS вручную
- operator протестировал настройку и забыл вернуть
- console/API change обошёл Git
- ресурс перестал совпадать с Terraform config

Это называется **drift**.

Если drift не ловить рано:

- следующий plan становится непонятным
- следующий apply может неожиданно откатить или заменить ресурс
- команда перестаёт доверять Terraform как source of truth

В этом уроке строим **scheduled drift detection workflow**, который:

- запускается автоматически или вручную
- проверяет deployed environment против кода в `main`
- сохраняет proof artifacts
- даёт понятный результат:
  - `NO_DRIFT`
  - `DRIFT_DETECTED`
  - `PIPELINE_ERROR`

---

## Что Должно Получиться

- собрать scheduled GitHub Actions workflow для Terraform drift detection
- переиспользовать OIDC + remote backend из lesson 63
- использовать `terraform plan -detailed-exitcode` как основной сигнал
- отличать drift от pipeline failure
- сохранять читаемые evidence artifacts
- уметь выбрать triage path:
  - revert manual change
  - accept and codify
  - import/reconcile
  - investigate first

---

## Quick Path

1. Переиспользовать CI auth/backend model из lesson 63.
2. Создать scheduled workflow, который checkout-ит `main`.
3. Запустить `fmt`, `validate`, remote-backend `plan -detailed-exitcode`.
4. Сохранить:
   - raw plan output
   - `terraform show` output
   - drift decision file
5. Сделать один deliberate manual drift в AWS.
6. Доказать, что workflow его ловит.
7. Разобрать drift и вернуть clean state.

---

## Prerequisites

- lesson 60 completed: remote state и locking
- lesson 61 completed: safe state refactors
- lesson 63 completed: PR plan pipeline with OIDC
- есть стабильное env в AWS, управляемое Terraform
- понимать разницу между:
  - configuration change в Git
  - out-of-band change в AWS
  - state mapping issue

---

## Структура Урока

```text
lessons/64-drift-detection-and-change-awareness/
├── lesson.en.md
├── lesson.ru.md
├── README.md
├── proof-pack.en.md
├── proof-pack.ru.md
├── ci/
│   └── terraform-drift.yml
└── lab_64/
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
Scheduled GitHub Actions run
  |
  v
checkout main
  |
  +--> terraform fmt -check
  +--> terraform validate
  +--> terraform init (remote backend)
  +--> terraform plan -detailed-exitcode
             |
             +--> exit 0 => NO_DRIFT
             +--> exit 2 => DRIFT_DETECTED
             +--> exit 1 => PIPELINE_ERROR
  |
  v
artifact upload + decision file
```

Важное правило:

- workflow **detects**
- workflow не делает auto-apply

---

## A) Что Считается Drift

Drift означает:

- реальный AWS object больше не совпадает с Terraform configuration на `main`

Примеры:

- кто-то вручную изменил security group rule в AWS console
- tag поменяли через console/API
- `deletion_protection` у ALB переключили вне Terraform
- CloudWatch alarm threshold поменяли руками

Не drift:

- unmerged PR branch с намеренными Terraform changes
- local uncommitted edit
- pipeline formatting issue

Практическое правило:

> Drift detection запускается против deployed code на `main`, а не против feature branch.

---

## B) Core Signal: `terraform plan -detailed-exitcode`

Terraform возвращает:

- `0` -> no diff
- `1` -> error
- `2` -> diff exists

Для scheduled workflow на `main`:

- `1` это не drift, а pipeline/backend/provider problem
- `2` это drift signal

Локальный dry run из `envs`:

```bash
terraform init -reconfigure -backend-config=backend.hcl
terraform plan -detailed-exitcode -no-color -out=tfplan
echo $?
```

Интерпретация:

- `0` -> clean
- `1` -> сначала чини pipeline/tooling/backend
- `2` -> diff есть, нужен triage

---

## C) Workflow (`ci/terraform-drift.yml`)

```yaml
name: terraform-drift

on:
  # Scheduled drift check against deployed reality and the main branch code.
  schedule:
    - cron: '0 6 * * *'
  # Manual run is useful while learning and during incident triage.
  workflow_dispatch: {}

permissions:
  # Required for GitHub OIDC -> AWS assume-role.
  id-token: write
  contents: read

concurrency:
  # Drift detection is global for this env; keep only one active run.
  group: terraform-drift-lab64-main
  cancel-in-progress: true

env:
  TF_ROOT: lessons/64-drift-detection-and-change-awareness/lab_64/terraform
  TF_IN_AUTOMATION: true
  TF_INPUT: false
  AWS_REGION: ${{ vars.AWS_REGION || 'eu-west-1' }}

jobs:
  drift-detection:
    runs-on: ubuntu-latest

    defaults:
      run:
        shell: bash
        working-directory: ${{ env.TF_ROOT }}

    steps:
      - name: Checkout main
        uses: actions/checkout@v4
        with:
          ref: main

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
          role-session-name: gha-terraform-drift

      - name: Terraform fmt
        run: terraform fmt -check -recursive

      - name: Terraform init (no backend)
        run: terraform -chdir=envs init -backend=false -input=false -no-color

      - name: Terraform validate
        run: terraform -chdir=envs validate -no-color

      - name: Write backend.hcl
        working-directory: ${{ env.TF_ROOT }}/envs
        run: |
          # CI writes backend config from repo variables and never migrates state.
          cat > backend.hcl <<EOF2
          bucket       = "${{ vars.TF_STATE_BUCKET }}"
          key          = "lab64/dev/full/terraform.tfstate"
          region       = "${{ env.AWS_REGION }}"
          encrypt      = true
          use_lockfile = true
          EOF2

      - name: Terraform init (remote backend)
        run: terraform -chdir=envs init -reconfigure -backend-config=backend.hcl -input=false -no-color

      - name: Terraform plan (detect drift)
        id: drift_plan
        working-directory: ${{ env.TF_ROOT }}/envs
        run: |
          set +e
          terraform plan -detailed-exitcode -input=false -no-color -out=tfplan > plan.txt 2>&1
          ec=$?
          echo "exitcode=$ec" >> "$GITHUB_OUTPUT"

          if [ "$ec" -eq 0 ]; then
            echo "NO_DRIFT" > decision.txt
          elif [ "$ec" -eq 2 ]; then
            echo "DRIFT_DETECTED" > decision.txt
          else
            echo "PIPELINE_ERROR" > decision.txt
          fi

          exit 0

      - name: Terraform show
        working-directory: ${{ env.TF_ROOT }}/envs
        run: |
          if [ -f tfplan ]; then
            terraform show -no-color tfplan > tfplan.txt
          else
            : > tfplan.txt
          fi

      - name: Upload drift artifacts
        uses: actions/upload-artifact@v4
        with:
          name: terraform-drift
          path: |
            ${{ env.TF_ROOT }}/envs/plan.txt
            ${{ env.TF_ROOT }}/envs/tfplan.txt
            ${{ env.TF_ROOT }}/envs/decision.txt

      - name: Job summary
        working-directory: ${{ env.TF_ROOT }}/envs
        run: |
          {
            echo "## Terraform Drift Detection"
            echo
            echo "- decision: $(cat decision.txt)"
            echo "- artifact: terraform-drift"
          } >> "$GITHUB_STEP_SUMMARY"

      - name: Fail on drift
        if: steps.drift_plan.outputs.exitcode == '2'
        run: |
          echo "Drift detected. See terraform-drift artifact."
          exit 2

      - name: Fail on pipeline error
        if: steps.drift_plan.outputs.exitcode == '1'
        run: |
          echo "Pipeline error during drift check."
          exit 1
```

Копировать в:

- `.github/workflows/terraform-drift.yml`

Workflow делает:

- checkout `main`
- OIDC assume-role
- `fmt`
- `validate`
- remote backend init
- `terraform plan -detailed-exitcode`
- сохраняет `decision.txt`, `plan.txt`, `tfplan.txt`
- падает на `DRIFT_DETECTED` и `PIPELINE_ERROR`

Он не запускает `apply`.

---

## D) Decision Model: Что Делать Когда Drift Есть

Не каждый drift означает “сразу apply”.

Варианты triage:

### 1. Revert manual change

Используй когда:

- console/API change был случайным
- Terraform config всё ещё intended truth

### 2. Accept and codify

Используй когда:

- manual change оказался правильным
- Terraform code теперь устарел

Тогда:

- обновить код
- открыть PR
- review plan
- merge

### 3. Import/reconcile

Используй когда:

- объект создали или изменили вне Terraform так, что нужно чинить mapping/config
- нужен lesson 61 state surgery

### 4. Investigate first

Используй когда:

- diff непонятен
- plan output недостаточен
- возможно, это provider/schema/state issue

---

## E) Triage Runbook

Когда drift workflow падает с `DRIFT_DETECTED`:

1. Скачай artifact.
2. Прочитай:
   - `decision.txt`
   - `plan.txt`
   - `tfplan.txt`
3. Ответь:
   - что изменилось?
   - это manual drift, intended change или state issue?
4. Выбери:
   - revert in AWS
   - update Terraform code
   - import/state surgery
   - investigate first
5. Перезапусти drift workflow до `NO_DRIFT`.

---

## F) Drift Drills (Обязательные)

### Drill 1: Manual managed-tag drift

Поменяй руками **существующий Terraform-managed tag** в AWS.

Не добавляй произвольный новый tag на web instance из ASG. Отдельные web instances создаются Auto Scaling Group и в этой лабе не отслеживаются Terraform как самостоятельные `aws_instance` resources.

Используй SSM proxy instance:

```bash
SSM_PROXY_ID="$(terraform output -raw ssm_proxy_instance_id)"

aws ec2 create-tags \
  --resources "$SSM_PROXY_ID" \
  --tags Key=Role,Value=manual-change
```

Ожидаемый результат:

- workflow возвращает `DRIFT_DETECTED`
- plan показывает, что Terraform хочет вернуть `Role = "ssm-proxy"`

Почему это хороший drill:

- низкий blast radius
- легко объяснить в plan output

### Drill 2: Managed security group rule drift

Удали руками существующее Terraform-managed SG rule в AWS.

Не используй произвольное extra SG rule для этого drill. В этой лабе ingress rules описаны отдельными `aws_security_group_rule` resources, поэтому удаление managed rule даёт более понятный drift signal.

Удали правило, которое разрешает SSM proxy ходить к internal ALB:

```bash
ALB_SG_ID="$(terraform output -json security_groups | jq -r '.alb_sg')"
SSM_PROXY_SG_ID="$(terraform output -json security_groups | jq -r '.ssm_proxy_sg')"

aws ec2 revoke-security-group-ingress \
  --group-id "$ALB_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,UserIdGroupPairs=[{GroupId=$SSM_PROXY_SG_ID}]"
```

Ожидаемый результат:

- drift workflow падает
- plan показывает, что Terraform хочет пересоздать `aws_security_group_rule.alb_http_from_ssm_proxy`

Почему это важно:

- это production footgun
- missing rule может сломать private access path

### Drill 3: ALB setting drift

Вручную переключи Terraform-managed ALB attribute.

Используй `drop_invalid_header_fields`. Для drill это безопаснее, чем трогать deletion protection.

```bash
ALB_ARN="$(terraform output -raw alb_arn)"

aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn "$ALB_ARN" \
  --attributes Key=routing.http.drop_invalid_header_fields.enabled,Value=false
```

Проверь manual change:

```bash
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn "$ALB_ARN" \
  --query 'Attributes[?Key==`routing.http.drop_invalid_header_fields.enabled`]' \
  --output table
```

Ожидаемый результат:

- workflow обнаруживает drift
- plan показывает, что Terraform хочет вернуть `drop_invalid_header_fields = true`
- ты классифицируешь: revert или codify

---

## G) Как Правильно Делать Drill

Шаблон:

1. Baseline:
   - run drift workflow
   - докажи `NO_DRIFT`
2. Внеси один manual AWS change.
3. Run drift workflow again.
4. Сохрани:
   - failing run
   - artifact
   - triage note
5. Revert или codify change.
6. Run workflow again.
7. Докажи возврат к `NO_DRIFT`.

Для Drill 1 верни tag обратно:

```bash
SSM_PROXY_ID="$(terraform output -raw ssm_proxy_instance_id)"

aws ec2 create-tags \
  --resources "$SSM_PROXY_ID" \
  --tags Key=Role,Value=ssm-proxy
```

Для Drill 2 верни clean state через Terraform:

```bash
terraform apply
```

Для Drill 3 clean state тоже возвращается через Terraform:

```bash
terraform apply
```

Паттерн тот же:

- baseline
- fail
- fix
- clean

---

## H) Evidence Pack

Для каждого drill сохрани:

- workflow run result
- `decision.txt`
- `plan.txt`
- `tfplan.txt`
- короткий note:
  - какой drift внёс
  - как он проявился в plan
  - какой triage choice сделал
  - как вернул clean state

Готовый шаблон: `proof-pack.ru.md`.

---

## Common Pitfalls

- запускать drift detection на feature branch
- считать exit code `1` drift-ом
- auto-applying drift fixes из CI
- находить drift, но не фиксировать triage decision
- оставлять manual AWS changes

---

## Final Acceptance

Lesson 64 закрыт, если:

- [ ] scheduled/manual workflow detects drift через `detailed-exitcode`
- [ ] `NO_DRIFT`, `DRIFT_DETECTED`, `PIPELINE_ERROR` разделены
- [ ] минимум 2 real drift drills completed
- [ ] у каждого drift есть proof artifacts и triage decision
- [ ] clean state restored after drills

---

## Lesson Summary

- **Что изучил:** как безопасно обнаруживать и разбирать infrastructure drift.
- **Что практиковал:** scheduled plan workflow, detailed exit code, evidence collection, triage discipline.
- **Операционный фокус:** находить расхождение reality/code до того, как следующий apply станет сюрпризом.
- **Почему это важно:** drift сегодня становится опасным plan завтра.
