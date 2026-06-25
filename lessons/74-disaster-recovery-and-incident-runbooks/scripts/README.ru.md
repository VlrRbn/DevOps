# Скрипты урока 74

Эта папка содержит вспомогательные скрипты для Terraform incident recovery. Их задача - быстро собрать доказательства, зафиксировать состояние и подготовить решение по инциденту.

Скрипты не делают recovery автоматически. Это намеренно: восстановление state, `force-unlock`, `state push`, rollback и ручные изменения должны проходить через явное решение и проверку.

## Модель безопасности

- Скрипты не запускают `terraform apply`, `terraform destroy`, `terraform force-unlock`, `terraform state push` или S3 restore.
- Скрипты могут читать Terraform state, remote backend, Git metadata и AWS S3 object versions.
- Созданные evidence-файлы могут содержать чувствительные данные: state, account IDs, внутренние DNS-имена, IP-адреса, ARNs и значения из provider output.
- Raw evidence не нужно коммитить в публичный Git. Перед публикацией редактируй чувствительные поля или сохраняй только краткое summary.
- Для временных файлов можно задать `OUT_DIR`, чтобы писать evidence вне папки урока.

## Требования

- Terraform установлен и доступен в `PATH`.
- AWS CLI нужен для `list-state-versions.sh` и `runtime-health-check.sh`.
- `jq` нужен для `runtime-health-check.sh`.
- Terraform backend уже настроен для выбранного окружения.
- AWS credentials должны иметь права на чтение backend/state.
- Для S3 версий нужны права читать object versions.
- Для runtime health нужны read-only права на STS, ELBv2, Auto Scaling и CloudWatch.
- Команды запускаются из корня репозитория или из любого места, если указывать полный путь к скрипту.

## Скрипты

| Скрипт | Назначение | Меняет инфраструктуру/state? |
|---|---|---|
| `state-snapshot.sh` | Снимает текущий Terraform state и текущий plan перед recovery. | Нет |
| `post-incident-check.sh` | Делает post-incident `terraform plan` и сохраняет статус после recovery. | Нет |
| `runtime-health-check.sh` | Собирает runtime health evidence по ALB Target Group, ASG и CloudWatch alarms. | Нет |
| `list-state-versions.sh` | Показывает версии S3 object для Terraform state key. | Нет |
| `incident-decision-template.sh` | Генерирует Markdown-шаблон решения по инциденту. | Нет |

## `state-snapshot.sh`

Используй перед любым recovery-действием.

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/state-snapshot.sh dev
```

Свой каталог для evidence:

```bash
OUT_DIR=/tmp/l74-state-snapshot-dev \
lessons/74-disaster-recovery-and-incident-runbooks/scripts/state-snapshot.sh dev
```

Создаёт файлы:

```text
terraform-version.txt
git-sha.txt
git-status.txt
terraform-state-pull.json
terraform-state-pull-stderr.txt
terraform-state-pull-exitcode.txt
current-plan.txt
current-plan-exitcode.txt
snapshot-summary.txt
```

Важно: `terraform-state-pull.json` почти всегда чувствительный. Не публикуй его без редактирования.

## `post-incident-check.sh`

Используй после recovery, rollback, fix-forward или ручной коррекции.

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/post-incident-check.sh dev
```

Скрипт печатает один из статусов:

- `CLEAN` - `terraform plan` вернул exit code `0`, изменений нет.
- `DRIFT_OR_DIFF` - `terraform plan` вернул exit code `2`, есть изменения или drift.
- `ERROR` - `terraform plan` завершился ошибкой.

Скрипт завершится с `0` для `CLEAN`, `2` для `DRIFT_OR_DIFF` и `1` для `ERROR`.

Создаёт файлы:

```text
terraform-version.txt
git-sha.txt
git-status.txt
post-incident-plan.txt
post-incident-plan-exitcode.txt
post-incident-summary.txt
```

`DRIFT_OR_DIFF` не всегда означает аварию. Это означает, что план нужно прочитать и принять решение.

## `runtime-health-check.sh`

Используй после Terraform-level проверки, чтобы собрать runtime evidence.

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/runtime-health-check.sh dev
```

Скрипт проверяет:

- ALB Target Group health;
- ASG instance lifecycle/health;
- CloudWatch alarm states для release/safety alarms.

Он не делает `curl` к внутреннему ALB. ALB в этой лабе private, поэтому с локальной машины он обычно доступен только через SSM port forwarding или VPN. Скрипт вместо этого использует AWS API.

Статусы:

- `RUNTIME_HEALTH_STATUS=HEALTHY` - targets healthy, критичные alarms не в `ALARM`.
- `RUNTIME_HEALTH_STATUS=WARN` - есть предупреждения, например `INSUFFICIENT_DATA`.
- `RUNTIME_HEALTH_STATUS=UNHEALTHY` - нет healthy targets или есть критичный alarm.
- `RUNTIME_HEALTH_STATUS=ERROR` - не удалось собрать evidence.

Создаёт файлы:

```text
terraform-version.txt
git-sha.txt
git-status.txt
runtime-inputs.txt
aws-caller-identity.json
target-health.json
target-health-states.txt
asg.json
asg-instances.txt
cloudwatch-alarms.json
cloudwatch-alarm-states.txt
runtime-health-summary.txt
```

Exit codes:

- `0` - runtime выглядит здоровым или есть только предупреждения;
- `1` - ошибка сбора evidence;
- `2` - runtime unhealthy.

## `list-state-versions.sh`

Используй, когда нужно понять, какие версии state есть в S3 backend.

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/list-state-versions.sh \
  "$TF_STATE_BUCKET" \
  "lab74/dev/full/terraform.tfstate"
```

Скрипт только показывает версии объектов. Он не восстанавливает, не копирует и не удаляет state.

Сохранять результат лучше так:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/list-state-versions.sh \
  "$TF_STATE_BUCKET" \
  "lab74/dev/full/terraform.tfstate" \
  > state-versions-dev.txt
```

Перед публикацией проверь, можно ли раскрывать bucket name и state key.

## `incident-decision-template.sh`

Генерирует шаблон решения по инциденту.

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/incident-decision-template.sh INC-001 dev \
  > incident-decision.md
```

Файл нужно заполнить вручную: симптом, диагностика, выбранный recovery path, approval, выполненные команды, verification и follow-up.

## Exit Codes

- `64` - неверные аргументы или окружение не входит в `dev|stage|prod`.
- `state-snapshot.sh` сохраняет exit code от `terraform state pull` и `terraform plan` в отдельные файлы. Он возвращает `1`, если state pull завершился ошибкой или если `terraform plan` вернул `1`.
- `post-incident-check.sh` сохраняет exit code от `terraform plan` и переводит его в статус `CLEAN`, `DRIFT_OR_DIFF` или `ERROR`. Он возвращает `0`, `2` или `1` соответственно.
- `runtime-health-check.sh` возвращает `0`, `1` или `2` и сохраняет статус в `runtime-health-summary.txt`.

## Troubleshooting

### `Terraform root not found`

Проверь, что запускаешь скрипт из актуальной папки урока и что существует `lab_74/terraform/envs/<env>`.

### `terraform state pull` завершился ошибкой

Обычно причины такие:

- backend не инициализирован;
- нет AWS credentials;
- нет доступа к S3 backend;
- неверный bucket/key в backend config;
- окружение ещё не применялось.

Даже при ошибке скрипт сохраняет evidence, чтобы было видно, что именно не сработало.

### `post-incident-check.sh` вернул `DRIFT_OR_DIFF`

Это значит, что Terraform видит изменения. Прочитай `post-incident-plan.txt` и реши, это ожидаемый rollback/fix-forward результат или новый drift.

### `runtime-health-check.sh` вернул `UNHEALTHY`

Проверь `target-health.json`, `asg.json` и `cloudwatch-alarm-states.txt`. Частые причины: targets ещё прогреваются, ASG не вывел instances в `InService`, application возвращает 5xx, health check path неверный.

### `list-state-versions.sh` ничего не показывает

Проверь bucket, state key, регион, AWS profile и включено ли versioning у S3 bucket.

## Связь с proof-pack

Минимально сохрани:

- путь к state snapshot folder;
- `snapshot-summary.txt`;
- `current-plan-exitcode.txt`;
- `post-incident-summary.txt`;
- `post-incident-plan-exitcode.txt`;
- `runtime-health-summary.txt`;
- заполненный `incident-decision.md`.

Raw state и полные планы сохраняй локально или в закрытом evidence-хранилище, но не в публичном репозитории.
