# Proof Pack Для Lesson 57

## Что Это

`Proof Pack` — это набор артефактов, который фиксирует:

- в каком состоянии была система в момент решения;
- какие сигналы ты видел (`alarms`, `refresh`, `target health`, `build sampler`);
- почему ты выбрал `CONTINUE` или `ROLLBACK`.

## Зачем Это Нужно

1. Чтобы решение по релизу было проверяемым.
2. Чтобы передать контекст другому инженеру без устных объяснений.
3. Чтобы в postmortem не восстанавливать события по памяти.
4. Чтобы видеть прогресс: на что ты опираешься при Go/No-Go.

## Когда Собирать

Минимум два раза:

1. До решения (checkpoint / canary окно).
2. Сразу после решения (после `CONTINUE` или `ROLLBACK`).

## Что Должно Входить

- `alarms.json` (safety + quality alarms)
- `instance-refreshes.json` (статусы, причины, время)
- `target-health.json` (health по target group)
- `scaling-activities.json` (launch/terminate причины)
- `build-sampler.txt` (распределение build-ответов)
- `baseline.log` / `canary.log` (если есть)
- `decision.txt` (явно: continue/rollback + reason)

## Стандартный Сбор (готовые команды)

```bash
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/l57-proof-$STAMP"
mkdir -p "$OUT"

export ASG_NAME="$(terraform output -raw web_asg_name)" \
export TG_ARN="$(terraform output -raw web_tg_arn)" \
export ALB_DNS="$(terraform output -raw alb_dns_name)" \
export PROJECT="$(terraform output -raw web_asg_name | sed 's/-web-asg$//')" \
export PROXY_ID="$(terraform output -raw ssm_proxy_instance_id)"

# 1) Alarms snapshot
aws cloudwatch describe-alarms \
  --alarm-names \
    "${PROJECT}-target-5xx-critical" \
    "${PROJECT}-alb-unhealthy-hosts" \
    "${PROJECT}-release-target-5xx" \
    "${PROJECT}-release-latency" \
  --output json > "$OUT/alarms.json"

# 2) Instance refresh status/history
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 10 \
  --output json > "$OUT/instance-refreshes.json"

# 3) Target health
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --output json > "$OUT/target-health.json"

# 4) Scaling activities
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-items 30 \
  --output json > "$OUT/scaling-activities.json"

# 5) Build sampler через SSM port-forward
aws ssm start-session \
  --target "$PROXY_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$ALB_DNS\"],\"portNumber\":[\"80\"],\"localPortNumber\":[\"18080\"]}"

# В другом локальном терминале:
ALB="http://127.0.0.1:18080"
for i in {1..80}; do
  curl -s -H 'Connection: close' "$ALB/" | egrep -i 'BUILD|Hostname|InstanceId' || true
done > "$OUT/build-sampler.txt"


# 6) Подцепить load-логи, если запускались
cp /tmp/l57_baseline_*.log "$OUT/" 2>/dev/null || true
cp /tmp/l57_canary_*.log "$OUT/" 2>/dev/null || true
```

## Файл Решения (обязательно)

```bash
cat > "$OUT/decision.txt" <<EOF
decision=CONTINUE   # CONTINUE или ROLLBACK
reason=release alarms OK, safety alarms OK, target health stable
timestamp=$(date -Is)
operator=$(whoami)
EOF
```

## Упаковка Для Хранения/Передачи

```bash
tar -C /tmp -czf "/tmp/$(basename "$OUT").tar.gz" "$(basename "$OUT")"
echo "saved: /tmp/$(basename "$OUT").tar.gz"
```

## Быстрая Проверка Качества Пака

- Есть ли `decision.txt` с конкретной причиной?
- Есть ли одновременно alarms + refresh + target health?
- Есть ли build sampler до/после решения?
- Есть ли canary/baseline логи (если тест запускался)?
- По артефактам можно понять, почему принято решение?

## Практическое Правило

Если решение нельзя защитить по артефактам, решение не считается завершённым.
