# Proof Pack Урока 68 - Controlled Terraform Apply Pipeline

Этот файл нужен как чеклист доказательств после прохождения лабы.

Рекомендуемая локальная папка:

```bash
mkdir -p lessons/68-controlled-terraform-apply-pipeline/evidence/l68-YYYYmmdd_HHMMSS
```

Не заливай raw evidence в Git, если там есть account ID, ARN, instance ID, bucket names или внутренние endpoints. Если хочешь сохранить в публичный репозиторий, сначала сделай redact.

## 1. Bootstrap Evidence

Сохрани outputs после доверенного локального bootstrap:

```bash
terraform output -no-color > evidence/l68-YYYYmmdd_HHMMSS/bootstrap-outputs-redacted.txt
terraform output -raw tf_plan_role_arn > evidence/l68-YYYYmmdd_HHMMSS/plan-role-arn-redacted.txt
terraform output -raw tf_apply_role_arn > evidence/l68-YYYYmmdd_HHMMSS/apply-role-arn-redacted.txt
```

Перед коммитом замаскируй AWS account ID и уникальные части role ARN.

## 2. GitHub Environment Evidence

Сохрани заметку или скрин, где видно:

- environment называется `terraform-dev`
- настроены required reviewers или wait timer
- apply workflow использует именно этот environment

Пример файла:

```text
evidence/l68-YYYYmmdd_HHMMSS/github-environment.txt
```

## 3. Repository Variables Evidence

Сохрани redacted список переменных:

```text
AWS_REGION=eu-west-1
TF_STATE_BUCKET=<redacted-tfstate-bucket>
TF_PLAN_ROLE_ARN=arn:aws:iam::<account-id-redacted>:role/<redacted-plan-role>
TF_APPLY_ROLE_ARN=arn:aws:iam::<account-id-redacted>:role/<redacted-apply-role>
TF_WEB_AMI_ID=ami-xxxxxxxxxxxxxxx
TF_SSM_PROXY_AMI_ID=ami-xxxxxxxxxxxxxxx
```

Реальные secret values не сохранять. AMI ID обычно не секрет, но для публичного proof pack лучше тоже маскировать.

## 4. Workflow Run Evidence

Скачай или сохрани GitHub Actions artifacts:

```text
lesson68-terraform-plan-dev
lesson68-terraform-apply-dev
```

Ожидаемые файлы:

- `plan.txt`
- `tfplan.txt`
- `tfplan.json`
- `destructive_changes.json`
- `apply.txt`
- `post_apply_plan.txt`
- `post_apply_exitcode.txt`

## 5. Decision Note

Создай короткий decision файл:

```text
mode: controlled apply
source_branch: main
environment: terraform-dev
decision: GO
reason: saved plan reviewed, environment approved, apply completed, post-apply drift check clean
post_apply_exit_code: 0
run_url: <github-actions-run-url>
operator: <name-or-handle>
timestamp: <UTC timestamp>
```

## 6. Failure Evidence

Если guardrail заблокировал apply, это тоже полезное доказательство. Сохраняй failed artifact для случаев:

- не хватает repository variable
- environment approval отклонён
- destructive action заблокирован
- post-apply plan вернул exit code `2`
- Terraform provider/backend ошибка

Заблокированный apply считается нормальным proof, если он показывает, что защита сработала.
