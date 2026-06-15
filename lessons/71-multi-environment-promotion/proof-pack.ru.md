# Пакет доказательств урока 71

Чеклист доказательств для multi-environment promotion.

Рекомендуемая игнорируемая папка:

```text
lessons/71-multi-environment-promotion/evidence/l71-YYYYmmdd_HHMMSS/
```

## 1. Матрица окружений

Сохрани короткую матрицу:

```text
env=dev   state_key=lab71/dev/full/terraform.tfstate   github_environment=terraform-dev
env=stage state_key=lab71/stage/full/terraform.tfstate github_environment=terraform-stage
env=prod  state_key=lab71/prod/full/terraform.tfstate  github_environment=terraform-prod
```

## 2. Метаданные promotion

Для каждого шага promotion сохрани:

```text
release_id=<release/change id>
source_env=none|dev|stage
target_env=dev|stage|prod
source_workflow_run_url=<required for stage/prod>
source_commit_sha=<required for stage/prod>
target_commit_sha=<current workflow commit>
```

Для `stage` и `prod` `source_commit_sha` должен совпадать с commit текущего workflow run.
Workflow также проверяет предыдущий run через GitHub API и ожидает artifact `lesson71-<source_env>-apply` с корректным `promotion-manifest.json`.

## 3. Доказательства plan по каждому окружению

Для каждого окружения, в которое выполнялся promotion, сохрани:

- `plan.txt`
- `tfplan.txt`
- `tfplan.json`
- `policy-results/policy-decision.txt`
- `policy-results/policy-deny.json`
- `policy-results/policy-warn.json`
- GitHub Step Summary
- проверенный source run URL для `stage/prod`
- имя artifact: `lesson71-<env>-plan`

## 4. Доказательства apply

Для каждого apply сохрани:

- `apply.txt`
- `apply-metadata.json`
- `post_apply_plan.txt`
- `post_apply_exitcode.txt`
- `promotion-manifest.json`, если post-apply drift check прошёл
- workflow run URL
- имя artifact: `lesson71-<env>-apply`
- заметку или скриншот о GitHub Environment approval

## 5. Решение о promotion

Создай `promotion-decision.txt`:

```text
PROMOTION=none->dev|dev->stage|stage->prod
release_id=<release/change id>
source_env=<env>
target_env=<env>
decision=GO|NO-GO
reason=<short reason>
reviewer=<name or handle>
timestamp=<UTC timestamp>
```

## 6. Доказательства изоляции

Сохрани доказательства, что:

- backend key совпадает с target env
- root output `environment` совпадает с target env
- root output `project_name` совпадает с target env
- plan role соответствует target env
- apply role соответствует target env через `TF_APPLY_ROLE_ARN_DEV/STAGE/PROD`
- policy artifacts относятся к тому же target env
- apply artifact использует exact saved plan из plan job
- `promotion-manifest.json` содержит тот же `release_id`, commit SHA, workflow run URL и `policy_decision=ALLOW`

## 7. Чеклист маскировки

Перед публикацией или commit проверь:

- AWS account IDs
- role ARNs
- state bucket name, если приватный
- instance IDs
- public IPs
- secret values
- полный `tfplan.json`, если resources/provider могут раскрывать sensitive data

## 8. Заметки по реальным сбоям

Если во время прохождения возникали эти ошибки, сохранить короткую заметку о причине и исправлении:

- `EntityAlreadyExists` для GitHub OIDC provider: окружение пыталось создать provider уровня account повторно; исправление - передать `github_oidc_provider_arn` или убрать provider из state через `terraform state rm` без удаления из AWS.
- `deny_missing_required_tags`: policy gate нашёл ресурсы с поддержкой тегов, но без обязательных тегов; исправление - добавить `local.tags` в module, а не обходить policy файлом исключений.
