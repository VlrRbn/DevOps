# Proof Pack For Lesson 57

## What It Is

`Proof Pack` is a set of artifacts that records:

- system state at decision time;
- signals you observed (`alarms`, `refresh`, `target health`, `build sampler`);
- why you chose `CONTINUE` or `ROLLBACK`.

## Why It Matters

1. Makes release decisions auditable.
2. Enables clean handoff without verbal context loss.
3. Prevents postmortem guesswork.
4. Builds consistent Go/No-Go discipline.

## When To Collect

At least twice:

1. Before decision (checkpoint / canary window).
2. Immediately after decision (`CONTINUE` or `ROLLBACK`).

## What Must Be Included

- `alarms.json` (safety + quality alarms)
- `instance-refreshes.json` (status, reason, timeline)
- `target-health.json` (target group health)
- `scaling-activities.json` (launch/terminate causes)
- `build-sampler.txt` (build response distribution)
- `baseline.log` / `canary.log` (if generated)
- `decision.txt` (explicit decision + reason)

## Standard Collection (ready-to-run commands)

```bash
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/l57-proof-$STAMP"
mkdir -p "$OUT"

export ASG_NAME="$(terraform output -raw web_asg_name)"
export TG_ARN="$(terraform output -raw web_tg_arn)"
export ALB_DNS="$(terraform output -raw alb_dns_name)"
export PROJECT="$(terraform output -raw web_asg_name | sed 's/-web-asg$//')"
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

# 5) Build sampler via SSM port-forward
aws ssm start-session \
  --target "$PROXY_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$ALB_DNS\"],\"portNumber\":[\"80\"],\"localPortNumber\":[\"18080\"]}"

# In another local terminal:
ALB="http://127.0.0.1:18080"
for i in {1..80}; do
  curl -s -H 'Connection: close' "$ALB/" | egrep -i 'BUILD|Hostname|InstanceId' || true
done > "$OUT/build-sampler.txt"

# 6) Attach load logs if present
cp /tmp/l57_baseline_*.log "$OUT/" 2>/dev/null || true
cp /tmp/l57_canary_*.log "$OUT/" 2>/dev/null || true
```

## Decision File (mandatory)

```bash
cat > "$OUT/decision.txt" <<DECISION_EOF
decision=CONTINUE   # CONTINUE or ROLLBACK
reason=release alarms OK, safety alarms OK, target health stable
timestamp=$(date -Is)
operator=$(whoami)
DECISION_EOF
```

## Archive For Storage/Handoff

```bash
tar -C /tmp -czf "/tmp/$(basename "$OUT").tar.gz" "$(basename "$OUT")"
echo "saved: /tmp/$(basename "$OUT").tar.gz"
```

## Quick Quality Check

- Is `decision.txt` present with explicit reason?
- Do you have alarms + refresh + target health together?
- Do you have build sampler before/after decision?
- Are baseline/canary logs present when load was executed?
- Can another engineer understand the decision from artifacts only?

## Practical Rule

If a decision cannot be defended with artifacts, the decision is not complete.
