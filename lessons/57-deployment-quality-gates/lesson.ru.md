# lesson_57

---

# Deployment Quality Gates (Load, Latency, SLO-Style Release Rules)

**Date:** 2026-03-01

**Фокус:** перейти от «rollout завершился» к «rollout прошёл по качеству», добавив quality-gates по latency и error-поведению.

**Mindset:** релиз по доказательствам.

## Карта Моделей Деплоя

Этот урок продолжает ту же ветку, что и 55-56.

| Модель | Основная идея | Сильная сторона | Стоимость/сложность | Где лучше использовать |
|---|---|---|---|---|
| Blue/Green | две среды, переключение трафика | самый быстрый rollback | выше стоимость | самый безопасный cutover |
| Rolling Refresh | один флот, поэтапная замена | дешевле и проще | rollback слабее, чем в blue/green | небольшие и средние сервисы |
| Canary / Weighted | сначала малый %, потом расширение | лучший контроль рисков | выше операционная сложность | рискованные релизы |

- lesson 55: deployment engine (`Instance Refresh`)
- lesson 56: safety guardrails (`auto rollback`, checkpoints, alarm-gates)
- **lesson 57**: quality gates (latency + errors под контролируемой нагрузкой)

---

## Зачем Этот Урок

Деплой может быть «successful», но плохим для пользователей:

- заметно растёт latency
- деградирует error budget без мгновенного падения
- capacity выглядит нормально, но качество ответа хуже

Quality gates отвечают на один вопрос на checkpoint:

> «Продолжаем rollout или откатываемся сейчас?»

---

## Quick Path (20–30 min)

1. Подтверди, что baseline alarms в `OK`.
2. Добавь две release-alarms в Terraform: release target 5xx + release latency.
3. Применяй Terraform и проверь состояние alarm.
4. Собери AMI `57-02` и обнови `web_ami_id`.
5. Запусти rollout (`terraform apply`).
6. В checkpoint-режиме (`[50]`) запусти 5-минутный canary load.
7. Прими решение Go/No-Go по gate-правилам.
8. Доведи rollout до 100% или откатись на known-good.

---

## Целевая Архитектура

```text
Proxy load tool -> ALB -> TG -> ASG (Instance Refresh + checkpoint)
                     |
                     +-> CloudWatch metrics
                     +-> Safety alarms (lesson 56)
                     +-> Quality alarms (lesson 57)
```

Важное разделение:

- **Safety alarms:** защищают здоровье платформы и быстро откатывают при явной поломке.
- **Quality alarms:** защищают пользовательское качество релиза.

---

## Inputs (скопируй перед запуском)

Запускать из:

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs
```

Установи переменные:

```bash
export ASG_NAME="$(terraform output -raw web_asg_name)"
export TG_ARN="$(terraform output -raw web_tg_arn)"
export ALB_DNS="$(terraform output -raw alb_dns_name)"
export PROJECT="$(terraform output -raw web_asg_name | sed 's/-web-asg$//')"
printf "ASG=%s\nTG=%s\nALB=%s\nPROJECT=%s\n" "$ASG_NAME" "$TG_ARN" "$ALB_DNS" "$PROJECT"
```

Открой proxy session (для internal ALB проверок/нагрузки):

```bash
aws ssm start-session --target "$(terraform output -raw ssm_proxy_instance_id)"
```

Внутри proxy session:

```bash
ALB="http://$ALB_DNS"
```

---

## Goals / Критерии успеха

- [ ] Две quality-gates определены и наблюдаемы (`release-target-5xx`, `release-latency`)
- [ ] На checkpoint используется стандартизованный canary load profile
- [ ] Решение Continue/Rollback принимается только по метрикам + alarm
- [ ] Решение и результат подтверждены proof pack выводами

---

## Preconditions

- baseline из lesson 56 работает (refresh, checkpoint, rollback path)
- тело ответа включает `BUILD_ID` / host identity
- ALB доступен через SSM proxy
- Terraform + Packer + AWS CLI настроены

Жёсткое правило: в фазе принятия решения никаких «ручных фиксов» на инстансах.

---

## A) Определяем Quality Gates

### Gate 1: release error gate (hard stop)

Сигнал:

- `HTTPCode_Target_5XX_Count`

Правило:

- устойчивый нетривиальный 5xx на canary => rollback.

Порог для лабы:

- `threshold = 2`, `period = 60`, `evaluation_periods = 2`

### Gate 2: release latency gate (quality stop)

Сигнал:

- `TargetResponseTime` (Average)

Правило:

- если latency стабильно выше порога в canary-окне => rollback или hold.

Порог для лабы:

- `threshold = 0.5` seconds
- `period = 60`
- `evaluation_periods = 5`

### Стандарт canary-окна

Тестовые условия должны быть фиксированными:

- длительность: 5 минут
- тот же endpoint
- те же concurrency/threads
- тот же proxy host

Если профиль нагрузки меняется, решение по gate считается недействительным.

---

## B) Добавляем Release Gate Alarms в Terraform

Редактируй:

`lessons/57-deployment-quality-gates/lab_57/terraform/modules/network/monitoring.tf`

Добавь две alarms:

```hcl
resource "aws_cloudwatch_metric_alarm" "release_target_5xx" {
  alarm_name          = "${var.project_name}-release-target-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }

  alarm_description = "Release quality gate: backend 5xx regression"
}

resource "aws_cloudwatch_metric_alarm" "release_latency" {
  alarm_name          = "${var.project_name}-release-latency"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 0.5
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }

  alarm_description = "Release quality gate: backend latency regression"
}
```

Применение:

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs
terraform fmt -recursive
terraform plan
terraform apply
```

Проверка:

```bash
aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT}-release-target-5xx" "${PROJECT}-release-latency" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName,Threshold]' \
  --output table
```

---

## C) Safety vs Quality Wiring

Рекомендация:

- оставляй safety alarms из lesson 56 в ASG `alarm_specification` (жёсткая защита)
- quality alarms из lesson 57 используй для Go/No-Go на checkpoint (операторское решение)

Почему так:

- safety rollback должен быть детерминированным и малошумным
- quality gates обычно строже и чувствительнее к контексту

---

## D) Runbook: Baseline -> Canary -> Decision

### Step 0. Baseline snapshot

```bash
aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT}-target-5xx-critical" "${PROJECT}-alb-unhealthy-hosts" "${PROJECT}-release-target-5xx" "${PROJECT}-release-latency" \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table

aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table
```

Ожидание: все alarms в `OK`, targets healthy.

Опционально: собери отдельный proxy AMI с `wrk` (чтобы не зависеть от NAT во время лабы)

```bash
cd lessons/57-deployment-quality-gates/lab_57/packer/ssm_proxy
packer build -var 'build_id=57-wrk' .
```

Полученный AMI поставь в `ssm_proxy_ami_id` (`terraform.tfvars`), затем:

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs
terraform plan
terraform apply
```

### Step 1. Baseline load на текущем build

Используй один фиксированный профиль и не меняй его между baseline и canary.

Базовый путь (работает без NAT, не требует установки пакетов):

```bash
log="/tmp/l57_baseline_$(date +%Y%m%d_%H%M%S).log"
end=$(( $(date +%s) + 180 )) # 3 минуты
while [ "$(date +%s)" -lt "$end" ]; do
  seq 1 80 | xargs -n1 -P20 -I{} \
    curl -s -o /dev/null -w "%{http_code} %{time_total}\n" "$ALB/"
done >> "$log"

awk '$1 ~ /^2/ {ok++; t+=$2} $1 !~ /^2/ {bad++}
END {total=ok+bad; printf "baseline total=%d ok=%d bad=%d avg=%.3fs\n", total, ok, bad, (ok?t/ok:0)}' "$log"
```

Опционально (`wrk`/`ab`), если уже установлены или есть NAT:

```bash
# wrk пример
wrk -t4 -c80 -d180s "$ALB/"

# ab пример
ab -t 180 -c 80 "$ALB/"
```

### Step 2. Deploy нового build

```bash
cd lessons/57-deployment-quality-gates/lab_57/packer/web
packer build -var 'build_id=57-02' .
```

Поставь новый AMI в `terraform.tfvars`, затем:

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs
terraform plan
terraform apply
```

### Step 3. Checkpoint canary test

Если тренируешь checkpoint-процедуру, используй `checkpoint_percentages = [50]` в ASG preferences.

На checkpoint:

```bash
log="/tmp/l57_canary_$(date +%Y%m%d_%H%M%S).log"
end=$(( $(date +%s) + 300 )) # 5 минут
while [ "$(date +%s)" -lt "$end" ]; do
  seq 1 80 | xargs -n1 -P20 -I{} \
    curl -s -o /dev/null -w "%{http_code} %{time_total}\n" "$ALB/"
done >> "$log"

awk '$1 ~ /^2/ {ok++; t+=$2} $1 !~ /^2/ {bad++}
END {total=ok+bad; printf "canary total=%d ok=%d bad=%d avg=%.3fs\n", total, ok, bad, (ok?t/ok:0)}' "$log"
```

Опционально если доступно:

```bash
wrk -t4 -c80 -d300s "$ALB/"
```

Параллельно в локальном shell:

```bash
watch -n 15 "aws cloudwatch describe-alarms \
  --alarm-names '${PROJECT}-release-target-5xx' '${PROJECT}-release-latency' \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
  --output table"
```

### Step 4. Decision rules

Продолжай rollout только если одновременно:

- release alarms остаются `OK`
- safety alarms остаются `OK`
- target health стабилен
- sampler показывает mixed/advancing rollout без признаков ошибки

Если любой gate провален — rollback.

Decision matrix:

| Наблюдение | Решение |
|---|---|
| Safety alarms `OK`, quality alarms `OK`, target health стабильный | **GO** (продолжать rollout) |
| Safety alarms `OK`, но quality alarms флапают/на границе | **HOLD** (продлить canary и перепроверить) |
| Любой safety alarm в `ALARM` или явная деградация target health | **ROLLBACK** |
| Quality alarms устойчиво в `ALARM` на фиксированном canary-профиле | **ROLLBACK** |

---

## E) Build Sampler / Evidence Commands

Подробный сбор артефактов: `lessons/57-deployment-quality-gates/proof-pack.ru.md`.

### 1) Build distribution sampler

```bash
for i in {1..80}; do
  curl -s -H 'Connection: close' "$ALB/" | egrep -i 'BUILD|Hostname|InstanceId' || true
done
```

### 2) Release alarm snapshot

```bash
aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT}-release-target-5xx" "${PROJECT}-release-latency" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateUpdatedTimestamp]' \
  --output table
```

### 3) Refresh status

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 5 \
  --query 'InstanceRefreshes[*].[Status,PercentageComplete,StatusReason,StartTime,EndTime]' \
  --output table
```

### 4) Target health

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason,TargetHealth.Description]' \
  --output table
```

### 5) Scaling activities

```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-items 20 \
  --query 'Activities[*].[StartTime,StatusCode,Description,Cause]' \
  --output table
```

---

## F) Drills

## Drill 1 — Good release with quality gates (`57-01` -> `57-02`)

1. Прогони baseline load (3 min).
2. Деплой `57-02` и дойди до checkpoint.
3. Прогони canary load (5 min).
4. Все alarms остаются `OK`.
5. Доведи rollout до 100%.

Критерии успеха:

- [ ] ни один release gate alarm не сработал
- [ ] ни один safety alarm не сработал
- [ ] финальное состояние mostly/all `BUILD=57-02`

---

## Drill 2 — Forced latency gate failure (mechanics drill)

Цель: проверить механику gate без поломки fleet.

Метод (безопасно для лабы): временно ужми latency threshold (например до `0.05`) для `release-latency`, сделай apply, прогони тот же canary load.

Ожидание:

- `release-latency` переходит в `ALARM`
- решение = rollback/hold

Затем верни threshold обратно (`0.5`) и сделай apply.

Критерии успеха:

- [ ] переход latency gate подтверждён
- [ ] rollback/hold решение задокументировано по evidence

---

## Drill 3 — Error regression (`57-bad`) with rollback

Используй intentionally broken AMI path (тот же паттерн, что в lesson 56):

```bash
cd lessons/57-deployment-quality-gates/lab_57/packer/web
packer build -var 'build_id=57-bad' .
```

Деплой `57-bad`, прогони canary load, зафиксируй реакцию gate/alarm, откатись на known-good AMI.

Критерии успеха:

- [ ] 5xx-сигнал стал триггером rollback-решения
- [ ] финальное состояние возвращено на known-good build

---

## Drill 4 — Write team-ready Go/No-Go rules (5 lines)

Зафиксируй локальные правила:

1. Если `release-target-5xx` = `ALARM` -> rollback immediately.
2. Если `release-latency` = `ALARM` весь evaluation window -> rollback/hold.
3. Если safety alarms падают (`target-5xx-critical`, `alb-unhealthy`) -> rollback immediately.
4. Если alarms чистые и target health стабилен -> continue.
5. Каждое решение сопровождается proof pack артефактами.

Критерии успеха:

- [ ] умеешь принять release-решение без SSH на инстансы

---

## G) Pitfalls

- меняется профиль нагрузки между baseline и canary
- safety и quality alarms смешиваются без правил
- смотришь только CPU и игнорируешь ALB metrics
- после решения не сохраняешь proof artifacts
- не возвращаешь временные тестовые thresholds

---

## Final Acceptance

- [ ] release quality alarms добавлены и проверены
- [ ] canary decision process выполнен по метрикам
- [ ] rollback path проверен и для quality failure, и для error failure
- [ ] proof pack собран и приложен
- [ ] runbook можно переиспользовать в следующем deployment lesson

---

## Security Checklist

- [ ] в release workflow не добавлен SSH
- [ ] IMDSv2 остаётся обязательным в Launch Template
- [ ] секреты не запекаются в AMI
- [ ] alarms привязаны к конкретным operator actions
- [ ] rollout и rollback выполняются evidence-driven

---

## Lesson Summary

После lesson 57 ты умеешь:

- сохранить safety guardrails из lesson 56
- добавить quality-oriented release gates (latency + errors)
- запускать консистентные canary-проверки на checkpoint
- принимать воспроизводимые Go/No-Go решения на основе evidence
