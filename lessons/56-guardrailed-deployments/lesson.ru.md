# lesson_56

---

# Guardrailed Deployments (Auto Rollback, Checkpoints, Skip Matching)

**Date:** 2026-02-24

**Фокус:** превратить Instance Refresh в безопасный pipeline релизов с:

- alarm-gates в CloudWatch
- automatic rollback
- checkpoints
- skip matching

## Карта Моделей Деплоя

Этот урок не заменяет Blue/Green или Canary. Он добавляет guardrails к модели **single-fleet rolling** из lesson 55.

| Модель | Основная идея | Сильная сторона | Стоимость/сложность | Где лучше использовать |
|---|---|---|---|---|
| Blue/Green | две среды, переключение трафика | самый быстрый rollback | выше стоимость | самый безопасный cutover |
| Rolling Refresh | один флот, поэтапная замена | дешевле и проще | rollback слабее, чем в blue/green | небольшие и средние сервисы |
| Canary / Weighted | сначала малый %, потом расширение | лучший контроль рисков | выше операционная сложность | рискованные релизы |

В этом уроке фокус именно на **guardrails для Rolling Refresh**: alarm-gates, auto rollback, checkpoints, skip matching.

---

## Зачем Этот Урок

`lesson_55` дал engine деплоя:

- смена AMI в Launch Template
- запуск refresh
- наблюдение и ручной rollback при проблеме

`lesson_56` добавляет защиту платформы:

- авто-откат по сигналам alarm
- checkpoint-стопы для контролируемой валидации
- skip matching для снижения лишнего churn

Идея урока: уменьшить blast radius, а не усложнить процесс.

---

## Quick Path (20–30 min)

1. Убедись, что alarms в `OK`.
2. Добавь guardrails в ASG `instance_refresh.preferences`.
3. Выполни `terraform apply`.
4. Собери `56-02` AMI и обнови `web_ami_id`.
5. Выполни `terraform apply` (refresh стартует).
6. Наблюдай refresh + target health + alarms.
7. Проверяй прогресс выката по `BUILD_ID` и состоянию target/alarm.
8. Дождись завершения и подтверди, что остался только `56-02`.
9. Прогони bad AMI drill и проверь auto rollback.
10. Сохрани proof pack.

---

## Целевая Архитектура

```text
ALB + TargetGroup -> CloudWatch Alarms (target_5xx, unhealthy_hosts)
         |
         v
ASG (single fleet, Instance Refresh)
  - auto_rollback = true
  - alarm_specification = [ ... ]
  - checkpoint_percentages = [100] (lab completion mode)
  - checkpoint_delay = 180
  - skip_matching = true
```

Для checkpoint-тренировки временно переключай `checkpoint_percentages` на `[50]`.

---

## Inputs (скопируй перед запуском)

Рабочая директория:

```bash
cd lessons/56-guardrailed-deployments/lab_56/terraform/envs
```

Установи переменные:

```bash
export ASG_NAME="$(terraform output -raw web_asg_name)"
export TG_ARN="$(terraform output -raw web_tg_arn)"
export ALB_DNS="$(terraform output -raw alb_dns_name)"
export PROJECT="$(terraform output -raw web_asg_name | sed 's/-web-asg$//')"
```

Открой SSM proxy session (для internal ALB):

```bash
aws ssm start-session --target "$(terraform output -raw ssm_proxy_instance_id)"
```

Внутри SSM-сессии:

```bash
ALB_DNS="internal-...elb.amazonaws.com"
```

Базовый снимок состояния:

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table
```

и

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 3 \
  --query 'InstanceRefreshes[*].[InstanceRefreshId,Status,PercentageComplete,StartTime,EndTime,StatusReason]' \
  --output table

  # или

aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 3 \
  --query 'length(InstanceRefreshes)'
```

---

## Goals / Критерии успеха

- [ ] Refresh безопасно раскатывает новую AMI
- [ ] Guardrail alarms реально подключены к refresh
- [ ] Bad rollout триггерит автоматический rollback
- [ ] Checkpoint даёт контролируемое окно валидации
- [ ] Skip matching снижает лишние замены
- [ ] Собран evidence: refresh state, alarm states, target health, traffic sample

---

## Preconditions

- baseline из `lesson_55` работает end-to-end
- ответ приложения содержит `BUILD_ID` (или эквивалент)
- ALB доступен через SSM proxy model
- Terraform + Packer + AWS CLI настроены

Жёсткое правило: никаких ad-hoc правок на инстансах во время rollout.

---

## A) Определяем Release-Сигналы (CloudWatch Alarms)

### Signal policy

Используй alarms, которые отражают impact для пользователя/ёмкости.

Два базовых gate-сигнала для rollback:

1. `HTTPCode_Target_5XX_Count` (ошибки backend)
2. `UnHealthyHostCount` (потеря здоровых target)

### Почему не “все возможные alarms”

Слишком много alarms делает rollback шумным и недетерминированным.
Guardrails должны быть строгими, но предсказуемыми.

### Минимальные Примеры Alarm

`Target 5XX`:

```hcl
resource "aws_cloudwatch_metric_alarm" "target_5xx_critical" {
  alarm_name          = "${var.project_name}-target-5xx-critical"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }
}
```

`UnHealthyHostCount`:

```hcl
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy" {
  alarm_name          = "${var.project_name}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }
}
```

### Проверка Alarm Перед Деплоем

```bash
aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT}-target-5xx-critical" "${PROJECT}-alb-unhealthy-hosts" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName,Threshold]' \
  --output table
```

Ожидание: оба alarms в `OK` до старта refresh.

---

## B) Включаем Guardrails В ASG Instance Refresh

Редактируй:

`lessons/56-guardrailed-deployments/lab_56/terraform/modules/network/asg.tf`

Добавь/проверь guardrails в preferences:

```hcl
instance_refresh {
  strategy = "Rolling"
  preferences {
    min_healthy_percentage = var.asg_min_healthy_percentage
    instance_warmup        = var.asg_instance_warmup_seconds

    auto_rollback          = true
    checkpoint_percentages = [100]
    checkpoint_delay       = var.asg_checkpoint_delay_seconds
    skip_matching          = true

    alarm_specification {
      alarms = [
        aws_cloudwatch_metric_alarm.target_5xx_critical.alarm_name,
        aws_cloudwatch_metric_alarm.alb_unhealthy.alarm_name
      ]
    }
  }

  triggers = ["launch_template"]
}
```

### Для Чего Нужна Каждая Настройка

- `auto_rollback = true`:
  fail-safe поведение при плохих сигналах.
- `alarm_specification`:
  привязывает решения refresh к объективным метрикам.
- `checkpoint_percentages = [100]`:
  без mid-stop, проще пройти full drill.
- `checkpoint_delay`:
  актуален, когда checkpoints включены (например, режим `[50]`).
- `skip_matching = true`:
  не заменяет инстансы, которые уже соответствуют desired config.

Режим checkpoint:

- `[100]` для непрерывного завершения rollout
- `[50]` для явного human decision gate в середине

### Применение

```bash
cd lessons/56-guardrailed-deployments/lab_56/terraform/envs
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Критерии успеха:

- [ ] apply успешен
- [ ] guardrails видны в ASG refresh preferences

---

## C) Операционный Runbook (Нормальный Good Rollout)

### Что / Зачем / Когда

- **Что:** пошаговый безопасный выкат новой AMI через Instance Refresh + guardrails.
- **Зачем:** снизить риск, получить воспроизводимый rollout и понятный rollback path.
- **Когда:** каждый раз перед релизом и особенно при изменениях, влияющих на startup/health.

### Шаг 0 — Базовый Снимок

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 5

aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT}-alb-5xx-critical" "${PROJECT}-target-5xx-critical" "${PROJECT}-alb-unhealthy-hosts" \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table

aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table
```

Ожидание: нет активного failed refresh, все target healthy.

### Шаг 1 — Сборка Следующей AMI

```bash
cd lessons/56-guardrailed-deployments/lab_56/packer/web
packer build -var 'build_id=56-02' .
```

Сохрани новый AMI ID из вывода Packer.

### Шаг 2 — Обновление Terraform Ввода

В `terraform.tfvars` обнови:

```hcl
web_ami_id = "ami-xxxxxxxxxxxxxxxxx"
```

Затем:

```bash
cd lessons/56-guardrailed-deployments/lab_56/terraform/envs
terraform plan
terraform apply
```

### Шаг 3 — Мониторинг Refresh

```bash
watch -n 10 "aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name '$ASG_NAME' \
  --max-records 1 \
  --query 'InstanceRefreshes[0].[Status,PercentageComplete,StatusReason]' \
  --output table"
```

### Шаг 4 — Параллельная Проверка Alarm

```bash
watch -n 15 "aws cloudwatch describe-alarms \
  --alarm-names '${PROJECT}-target-5xx-critical' '${PROJECT}-alb-unhealthy-hosts' \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
  --output table"
```

Target health:

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table
```

### Шаг 5 — Optional Checkpoint-режим (50%)

По умолчанию в лабе `checkpoint_percentages = [100]`, поэтому mid-pause нет.
Для тренировки checkpoint-процедуры выставь `checkpoint_percentages = [50]`, выполни apply и затем этот шаг.

Внутри SSM proxy session:

```bash
for i in {1..40}; do
  curl -s -H 'Connection: close' "http://$ALB_DNS/" | egrep -i 'BUILD|Hostname|InstanceId' || true
  sleep 1
done
```

Из локального терминала:

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table
```

Ожидание в 50% checkpoint mode:

- виден mixed `BUILD_ID` (`56-01` + `56-02`)
- нет устойчивого unhealthy target state
- guardrail alarms остаются `OK`

### Шаг 6 — Финальная Валидация

После завершения refresh:

- ALB sampling возвращает только `56-02`
- alarms остаются `OK`
- target health полностью `healthy`

---

## D) Практические Drill-сценарии

## Drill 1 — Good rollout с доказательствами

Стартовое состояние:

- fleet на `56-01`
- alarms в `OK`

Действия:

- выкати `56-02`
- наблюдай completion (и checkpoint только в режиме `[50]`)

Ожидание:

- mixed fleet на checkpoint (только при `[50]`)
- полный `56-02` в конце
- без rollback

Доказательства:

- refresh status timeline
- alarm state timeline
- target health snapshots
- curl sampler output

Критерии успеха:

- [ ] evidence собран и согласован

---

## Drill 2 — Bad AMI и автоматический rollback

Цель: доказать auto rollback без ручного вмешательства.

### Вариант A (чистый lab-метод)

Собери намеренно сломанный AMI с `build_id`, оканчивающимся на `-bad` (например `56-bad`).
`disable-nginx.sh` в Packer условный и активируется только для `build_id` вида `*-bad`.

Путь:

`lessons/56-guardrailed-deployments/lab_56/packer/web/scripts/disable-nginx.sh`

Далее выкати `56-bad`.

### Вариант B (быстрее, но шумнее)

Временно сломай app response/health поведение в bake pipeline, чтобы targets падали health checks.

Наблюдение:

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 5
```

Ожидание:

- один или несколько guardrail alarms переходят в `ALARM`
- refresh переходит в rollback/cancel outcome
- трафик/fleet возвращается на last known good AMI

1) Scaling activities (launch/terminate + причины)

```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-items 10 \
  --query 'Activities[*].[StartTime,StatusCode,Description,Cause]' \
  --output table
```

2) Какие инстансы в ASG и какие AMI на них

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus,LaunchTemplate.Version]' \
  --output table

# Затем используй instance IDs из таблицы:
aws ec2 describe-instances \
  --instance-ids <id1> <id2> \
  --query 'Reservations[*].Instances[*].[InstanceId,ImageId,LaunchTime]' \
  --output table
```

3) Текущее состояние refresh (последние записи)

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 3 \
  --query 'InstanceRefreshes[*].[InstanceRefreshId,Status,PercentageComplete,StartTime,EndTime,StatusReason]' \
  --output table
```

Критерии успеха:

- [ ] rollback произошёл автоматически
- [ ] без ручного cancel/terminate

---

## Drill 3 — Checkpoint Go/No-Go решение (training mode)

Перед drill выставь `checkpoint_percentages = [50]` и выполни apply.
На checkpoint принимай решение только по сигналам.

### Go/No-Go Матрица

| Signal | Continue | Rollback |
|---|---|---|
| `target_5xx` | кратковременные spikes, быстро возвращается в `OK` | устойчивые ошибки / alarm остаётся в `ALARM` |
| `UnHealthyHostCount` | краткий всплеск, восстанавливается до нуля | постоянные unhealthy targets |
| ALB sample (`BUILD_ID`) | mixed fleet без ошибок | mixed fleet с заметными fail responses |
| Refresh status reason | нормальный прогресс | повторяющийся failure reason/churn |

Критерии успеха:

- [ ] решение обосновано метриками/evidence, а не интуицией

---

## Drill 4 — Проверка поведения skip matching

Цель: понять влияние skip matching на churn.

Действия:

1. Внеси изменение, которое не требует замены уже matching инстансов.
2. Запусти refresh path.
3. Сравни replacement count/duration с прошлыми прогонами.

Ожидание:

- меньше лишних замен, когда инстансы уже совпадают с desired config

Важно:

- skip matching не заменяет drift management.

Критерии успеха:

- [ ] можешь объяснить, где skip matching помогает, а где скрывает assumptions

---

## E) Proof Pack (обязательные команды)

### 1) Сводка Refresh

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 5 \
  --query 'InstanceRefreshes[*].[InstanceRefreshId,Status,PercentageComplete,StartTime,EndTime,StatusReason]' \
  --output table
```

### 2) Состояние Alarm

```bash
aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT}-target-5xx-critical" "${PROJECT}-alb-unhealthy-hosts" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateUpdatedTimestamp]' \
  --output table
```

### 3) Таймлайн Target Health

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason,TargetHealth.Description]' \
  --output table
```

### 4) Выборка Build Identity (внутри proxy)

```bash
for i in {1..60}; do
  curl -s -H 'Connection: close' "http://$ALB_DNS/" | egrep -i 'BUILD|Hostname|InstanceId' || true
  sleep 1
done
```

### 5) Scaling Activities (видимость churn)

```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-items 30 \
  --query 'Activities[*].[StartTime,StatusCode,Description,Cause]' \
  --output table
```

---

## F) Шпаргалка По Интерпретации Сбоев

- Alarm `ALARM` + refresh rollback -> корректное guardrail-поведение
- Alarm `OK` + refresh fails -> чаще всего warmup/grace/checkpoint tuning issue
- Частые `UnHealthyHostCount` spikes -> проверь стабильность health endpoint и startup timing
- Высокий churn при skip matching -> проверь, что изменилось в Launch Template и AMI contract

---

## G) Типовые Ошибки

- Alarms слишком чувствительные -> ложные rollback loops
- Alarms слишком “мягкие” -> rollback приходит поздно
- `checkpoint_delay` слишком короткий -> нет времени на осмысленную валидацию
- нет build identity в ответе -> нет доказательств, только догадки
- skip matching ошибочно воспринимают как drift control

---

## Финальные критерии успеха

- [ ] good rollout завершён и подтверждён evidence
- [ ] bad rollout auto-rolled back через alarm gates
- [ ] proof pack собран и сохранён
- [ ] оператор может объяснить Go/No-Go decision path в 5 строк

---

## Security Checklist

- [ ] в deployment workflow не используется SSH
- [ ] IMDSv2 включён в Launch Template
- [ ] секреты не запекаются в AMI
- [ ] alarms привязаны к user-impact/capacity сигналам
- [ ] rollback path проверен до старта rollout

---

## Итоги Урока

- **Что изучил:** как превратить `ASG Instance Refresh` в безопасный деплой через `alarm gates`, `auto rollback`, `checkpoints`, `skip matching`.
- **Что практиковал:** хороший rollout (`56-02`), bad rollout (`56-bad`), наблюдение refresh через `describe-instance-refreshes`, `describe-target-health`, `describe-alarms`.
- **Ключевая мысль:** auto rollback защищает рантайм, но не меняет desired state в Terraform; после rollback нужно вернуть `web_ami_id` на known-good.
- **Операционный фокус:** evidence-first подход — решение `Go/No-Go` принимается по метрикам и статусам, а не “на глаз”.
- **Что должно уметь получаться:** отличать `single-fleet rolling` от `blue/green`, завершать rollout до 100% и доказывать результат proof-pack артефактами.
