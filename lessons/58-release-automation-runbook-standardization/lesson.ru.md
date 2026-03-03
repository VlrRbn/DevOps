# lesson_58

---

# Release Automation & Runbook Standardization

**Date:** 2026-03-03

**Фокус:** превратить gate-логику из lesson 57 в одну повторяемую release-команду.

**Mindset:** никаких release-решений без evidence.

---

## Зачем Этот Урок

В lesson_57 уже были:

- safety и quality alarms
- checkpoint-решение на canary
- дисциплина proof-pack

Но сам flow оставался в основном ручным.  
В lesson_58 стандартизируем тот же flow так, чтобы каждый релиз проходил одинаково.

---

## Что Должно Получиться

- один скрипт запускает load + snapshots + build sampling + decision
- единый результат решения: `GO` / `HOLD` / `ROLLBACK`
- переиспользуемый шаблон incident/release note
- одна папка артефактов на каждый запуск (с timestamp)

---

## Prerequisites

- lesson 57 завершён
- в Terraform outputs есть:
  - `web_asg_name`
  - `web_tg_arn`
  - `alb_dns_name`
- AWS CLI + Terraform настроены
- есть путь трафика до ALB:
  - либо запуск с proxy host
  - либо SSM port-forward + `--alb-url http://127.0.0.1:18080/`

---

## Lab Network Note

В этой лабе ALB внутренний.

- Путь с локальной машины: запуск через SSM port-forward (`127.0.0.1:18080`).
- Путь внутри VPC: запуск с хоста, у которого уже есть прямой маршрут до internal ALB.

Port-forward здесь используется в основном для того, чтобы запускать release-check и сохранять proof artifacts локально.

---

## Структура Урока

```text
lessons/58-release-automation-runbook-standardization/
├── incident-note.md
├── lesson.ru.md
├── README.md
├── templates/
│   └── incident-note.template.md
└── scripts/
    └── release-check.sh
```

---

## Standard Signal Contract

Автоматизация ожидает такие alarm names (из lesson_57):

- `${PROJECT}-target-5xx-critical` (safety)
- `${PROJECT}-alb-unhealthy-hosts` (safety)
- `${PROJECT}-release-target-5xx` (quality)
- `${PROJECT}-release-latency` (quality)

Правила решения:

- safety `ALARM` => `ROLLBACK`
- release 5xx `ALARM` => `ROLLBACK`
- release latency `ALARM` => `HOLD`
- иначе => `GO`

---

## Скрипт: One Command Release Check

Путь к скрипту:

- `lessons/58-release-automation-runbook-standardization/scripts/release-check.sh`

Что он делает:

1. читает Terraform outputs (`ASG`, `TG`, `ALB`, `PROJECT`)
2. запускает нагрузку (baseline/canary duration)
3. снимает snapshots: alarms/refresh/target health/scaling activities
4. делает build sampling из response body
5. считает gates и печатает решение
6. сохраняет timestamped artifact directory

### Использование

```bash
chmod +x lessons/58-release-automation-runbook-standardization/scripts/release-check.sh

# запуск из terraform env dir:
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs

# baseline run (3 минуты) — только если этот shell имеет прямой доступ к internal ALB
../../../../58-release-automation-runbook-standardization/scripts/release-check.sh \
  --mode baseline \
  --out-root /tmp

# canary run (5 минут) — только если этот shell имеет прямой доступ к internal ALB
../../../../58-release-automation-runbook-standardization/scripts/release-check.sh \
  --mode canary \
  --require-checkpoint \
  --out-root /tmp
```

Рекомендуемый запуск для internal ALB: через локальный SSM port-forward (2 терминала).

Терминал 1 (сессию не закрывать):

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs
export PROXY_ID="$(terraform output -raw ssm_proxy_instance_id)"
export ALB_DNS="$(terraform output -raw alb_dns_name)"

aws ssm start-session \
  --target "$PROXY_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$ALB_DNS\"],\"portNumber\":[\"80\"],\"localPortNumber\":[\"18080\"]}"
```

Терминал 2:

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs

# baseline (3 минуты)
../../../../58-release-automation-runbook-standardization/scripts/release-check.sh \
  --mode baseline \
  --alb-url http://127.0.0.1:18080/ \
  --out-root /tmp

# canary (5 минут, с проверкой checkpoint)
../../../../58-release-automation-runbook-standardization/scripts/release-check.sh \
  --mode canary \
  --require-checkpoint \
  --alb-url http://127.0.0.1:18080/ \
  --out-root /tmp
```

---

## Output Contract

Каждый запуск создаёт папку:

`/tmp/l58-<mode>-YYYYmmdd_HHMMSS/`

Файлы внутри:

- `alarms.json`
- `target-health.json`
- `instance-refreshes.json`
- `scaling-activities.json`
- `build-sampler.txt`
- `load.log`
- `load.summary.txt`
- `load.codes.txt`
- `decision.txt`
- `summary.json`

Это специально согласовано со стилем proof-pack из lesson_57 (те же сигналы и та же логика evidence).

---

## Шаблон Incident/Release Note

Путь к шаблону:

- `lessons/58-release-automation-runbook-standardization/templates/incident-note.template.md`

Как использовать:

```bash
cp lessons/58-release-automation-runbook-standardization/templates/incident-note.template.md \
   /tmp/l58-incident-note.md
```

Заполняй после каждого canary decision, используя `decision.txt` и `summary.json`.

---

## Runbook (Checkpoint)

1. Запусти instance refresh с checkpoint-режимом в ASG preferences.
2. Проверь, что ты действительно на checkpoint:
   ```bash
   aws autoscaling describe-instance-refreshes \
     --auto-scaling-group-name "$ASG_NAME" \
     --max-records 1 \
     --query 'InstanceRefreshes[0].[Status,PercentageComplete,StatusReason]' \
     --output table
   ```
   Ожидаемо: `InProgress` и `PercentageComplete=50` (для режима `[50]`).
3. На 50% checkpoint запусти canary check script (`--require-checkpoint` рекомендуется).
4. Прочитай `decision.txt`.
5. Действие:
   - `GO` => продолжить rollout
   - `HOLD` => продлить canary window, доразобраться
   - `ROLLBACK` => прервать и откатить сразу
6. Приложи artifact directory + incident note.

---

## Drills

### Drill 1: Healthy candidate -> GO

- раскатай good AMI
- запусти canary check на checkpoint
- ожидаемо: `DECISION=GO`

### Drill 2: Latency regression -> HOLD

1. Найди один web instance в текущем ASG:
   ```bash
   WEB_ID="$(aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names "$ASG_NAME" \
     --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
     --output text)"
   echo "$WEB_ID"
   ```
2. Открой SSM-сессию на этот инстанс и проверь `tc`:
   ```bash
   aws ssm start-session --target "$WEB_ID"
   command -v tc
   ```
3. Добавь задержку на инстансе:
   ```bash
   sudo tc qdisc add dev eth0 root netem delay 700ms 100ms
   sudo tc qdisc show dev eth0
   ```
4. Запусти canary check из терминала с доступом к ALB.
5. Ожидаемо: `DECISION=HOLD`, а release latency alarm стремится к `ALARM`.
6. Cleanup на web-инстансе:
   ```bash
   sudo tc qdisc del dev eth0 root
   sudo tc qdisc show dev eth0
   ```

### Drill 3: 5xx regression -> ROLLBACK

- раскатай bad AMI, который отдаёт 5xx
- запусти canary check
- ожидаемо: `DECISION=ROLLBACK`

---

## Pitfalls

- запуск против неверного ALB endpoint
- baseline и canary с разным load profile
- решение без папки артефактов
- переименовали alarms, но не обновили automation

---

## Final Acceptance

- [ ] одна команда даёт decision + evidence pack
- [ ] decision logic совпадает с состояниями alarms
- [ ] incident note заполнен из артефактов, а не “по памяти”
- [ ] команда может воспроизвести решение только по файлам

---

## Lesson Summary

Lesson_58 не про новый deployment model.  
Это стандартизация operational flow из lessons_55-57:

- те же guardrails
- те же gates
- меньше ручной вариативности
- выше auditability release-решений
