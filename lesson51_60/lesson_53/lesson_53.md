# lesson_53

---

# ALB Deep Dive: Health Checks, Failure Modes & Traffic Control

**Date:** 2026-02-01

**Focus:** Learn how **ALB actually decides** whether traffic flows or dies.

---

## Why this lesson matters

Almost all ALB production incidents look like this:

> “Instances exist, ASG is green, but traffic does not flow.”

The cause is almost always:

- health checks
- deregistration delay
- slow start
- wrong paths / codes

lesson_53 teaches you **not to guess**, but to **predict ALB behavior**.

---

## Target architecture (same, but deeper)

```
Client
  |
  v
ALB
 ├─ Health Checks
 ├─ Target States
 ├─ Deregistration Delay
 ├─ Slow Start
  |
  v
ASG (targets come and go)

```

---

## Goals / Acceptance Criteria

- [ ] You understand **all target states**
- [ ] You can explain why a target is unhealthy
- [ ] You can predict ALB behavior before testing
- [ ] You can intentionally break and recover traffic
- [ ] No surprises during scaling or refresh

---

### 0) Collect 3 values (from terraform outputs / console)

- ALB DNS (example: `internal-...elb.amazonaws.com`)
- Target Group ARN (example: `arn:aws:elasticloadbalancing:...:targetgroup/...`)
- ASG name (example: `lab50-web-asg`)

### Watch ALB/TargetGroup metrics (CloudWatch)

Minimum:

- `HealthyHostCount`, `UnHealthyHostCount`
- `TargetResponseTime`
- `HTTPCode_Target_5XX_Count`
- `RequestCount`, `HTTPCode_ELB_5XX_Count`

---

## A) ALB Health Checks

### Target states you must know

- `initial`**:** target is registered, but ALB has not accumulated enough successful checks yet.

**Why it matters:** in `initial`, **traffic may not flow**, even if the instance is “alive”. This is often confused with “ALB is broken”.

- `healthy`**:** target passed the healthy threshold.

**Why it matters:** “healthy” is **only about the health check endpoint**, not “users are happy”.

- `unhealthy`**:** ALB received enough consecutive health check failures.

**Why it matters:** ALB starts **cutting traffic** to this target. If ASG health check type is `ELB`, it may start replacing instances (sometimes that helps, sometimes it makes it worse).

- `draining`**:** target is leaving service, ALB stops sending new requests, but lets **in‑flight** requests finish until `deregistration delay`.

**Why it matters:** this is where “sometimes 502 during deploy/scale‑in” and “why users see errors for exactly 30 seconds” are born.

- `unused`**:** target group exists, but there are no targets or it is not attached to routing.

**Why it matters:** classic “ASG is green, instances exist, but TG is empty/wrong” — ALB is healthy, but traffic goes **nowhere**.

> “Key truth: ASG does not decide health. ALB does.”

---

### Health check parameters (and what they do)

- `path`**:** URL that ALB checks on the target.

**Why it matters:** most common failure: routing prefix changed, health check stayed old → all targets “dead”.

- `interval`**:** how often ALB checks.

**Why it matters:** shorter interval = faster detection, but more noise/load/flapping on edge latency.

- `timeout`**:** how long ALB waits for the health check response.

**Why it matters:** if timeout is close to real latency, you get “random unhealthy” during spikes.

- `healthy_threshold`**:** consecutive successes required to become healthy.

**Why it matters:** defines “how fast we recover”. Large value smooths noise but slows recovery.

- `unhealthy_threshold`**:** consecutive failures required to become unhealthy.

**Why it matters:** too small = **flapping**, too large = slow to cut truly dead instances.

- `matcher`**:** which HTTP codes count as success (usually 200, sometimes 200–399).

**Why it matters:** if your `/health` returns `301` or `204` and matcher is “200 only” — hello “everything is down” while it actually works.

---

**Practice:**

What happens if:

1. path returns `404`
2. nginx is “slow, but not dead”
3. instance boots slowly

---

### 1) `path` returns `404`

- health check = fail
- after `unhealthy_threshold` failures → `unhealthy`
- `UnHealthyHostCount` rises, `HealthyHostCount` drops
- traffic to the target stops
- if ASG uses ELB health → instance replacements may start, but **they won’t help**, because the issue is the path.

**Key lesson:** “recreate instances” fixes infra/service, but not **wrong checks**.

### 2) nginx is “slow, but not dead”

**Prediction:**

- if response time > `timeout` → health check fails, even if the page would eventually respond
- flapping is possible: healthy → unhealthy (especially with small thresholds)
- `TargetResponseTime` rises **before** targets start dropping

**Key lesson:** ALB cuts traffic based on the **SLO health check**, not “it kind of works”.

### 3) instance boots slowly

**Prediction:**

- early health checks fail (connection refused/timeout)
- target stays in `initial` / goes `unhealthy`
- if ASG health check grace period is too small → ASG can start churn (endless create/kill loop)

**Key lesson:** “boot race” is when autoscaling **kills** a service before it has time to go healthy.

---

## B) Health Check Tuning (Hands-on)

### Exercise 1 — Wrong Path

- Change health check path to `/healthz`
- Do **not** implement it
- Observe:
    - UnHealthyHostCount
    - ALB behavior
    - ASG reactions

What will happen?

1. When do targets become `unhealthy`?

    Formula: `Interval * UnhealthyThreshold`

    Example: 30s * 2 ≈ ~60–90 seconds.

2. What happens to user traffic?
    - If **all** targets go unhealthy → ALB returns **5xx** (usually 503) or “no healthy targets”.
3. What will ASG do?
    - If ASG health check type = `ELB` → it may start **churn** (instance replacements), but it *won’t fix it*, because the issue is the **check**, not the instances.

```bash
# Current TG health check settings
aws elbv2 describe-target-groups \
  --target-group-arns "$TG_ARN" \
  --query 'TargetGroups[0].{Path:HealthCheckPath,Interval:HealthCheckIntervalSeconds,Timeout:HealthCheckTimeoutSeconds,HealthyThr:HealthyThresholdCount,UnhealthyThr:UnhealthyThresholdCount,Matcher:Matcher}' \
  --output table

# Current target state
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{id:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason,desc:TargetHealth.Description}' \
  --output table

# Break it: change health check path to /healthz
aws elbv2 modify-target-group \
  --target-group-arn "$TG_ARN" \
  --health-check-path "/healthz"

# Check state/reason/description
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{id:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason,desc:TargetHealth.Description}' \
  --output table

```

What you should see:

- `healthy` → `unhealthy`
- reason/desc like: health checks failed

**CloudWatch metrics**

- `HealthyHostCount` drops toward 0
- `UnHealthyHostCount` rises
- `TargetResponseTime` may flatten/0 (no successful responses)

```bash
# Now check if ASG is replacing instances
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].{HealthCheckType:HealthCheckType,Grace:HealthCheckGracePeriod,Instances:Instances[].{Id:InstanceId,Health:HealthStatus,Lifecycle:LifecycleState}}' \
  --output table

# Recover
aws elbv2 modify-target-group \
  --target-group-arn "$TG_ARN" \
  --health-check-path "/"

```

**Interpretation:**

- If ASG starts cycling instances, it’s a **bad sign**: you are treating the symptom, not the cause.

**Acceptance:**

- [ ] **Predicted** the approximate target drop time (by interval/threshold)
- [ ] **Observed** the drop in **`describe-target-health`** (state+reason)
- [ ] **Confirmed** in CloudWatch (**`HealthyHostCount`**/**`UnHealthyHostCount`**)

---

### Exercise 2 — Slow Responses

Idea: backend is “alive”, but responds **too slowly** → ALB starts treating it as dead.

```bash
# Current TG health check settings
aws elbv2 describe-target-groups \
  --target-group-arns "$TG_ARN" \
  --query 'TargetGroups[0].{Path:HealthCheckPath,Interval:HealthCheckIntervalSeconds,Timeout:HealthCheckTimeoutSeconds,HealthyThr:HealthyThresholdCount,UnhealthyThr:UnhealthyThresholdCount,Matcher:Matcher}' \
  --output table

# Current target state
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{id:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason,desc:TargetHealth.Description}' \
  --output table

```

What will happen?

1. If I add **6s** of delay, what happens?
- If `HealthCheckTimeout` **< 6** → health checks start **failing** → targets go `unhealthy`.
- If `Timeout` **> 6** → health checks pass, but `TargetResponseTime` grows.
1. Will there be flapping?
- Yes, if timeout is “on the edge” and thresholds are small.

Simulate slow backend:

```bash
aws ssm start-session --target i-xxxxxxxxxxxxxxxx

sudo tc qdisc add dev ens5 root netem delay 6000ms
sudo tc qdisc show dev ens5

# If it didn’t create a new instance by itself
sudo tc qdisc del dev ens5 root
sudo tc qdisc show dev ens5
```

Observe:

- `TargetResponseTime` — should increase noticeably
- `HealthyHostCount/UnHealthyHostCount`
- `HTTPCode_Target_5XX_Count` — if 502/503 start due to no healthy targets

---

## C) Failure Mode (boot race)

### Idea

Instances “start”, but the service **doesn’t become healthy** before:

- health check/grace is too strict
- ASG decides the instance is bad and kills it
- churn begins: endless “launch → fail → terminate”

You can trigger boot race like this:

**Shorten ASG grace period**

```bash
# ASG parameters
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].{HealthCheckType:HealthCheckType,Grace:HealthCheckGracePeriod,Min:MinSize,Desired:DesiredCapacity,Max:MaxSize}' \
  --output table

# TG health check parameters
aws elbv2 describe-target-groups \
  --target-group-arns "$TG_ARN" \
  --query 'TargetGroups[0].{Timeout:HealthCheckTimeoutSeconds,Interval:HealthCheckIntervalSeconds,HealthyThr:HealthyThresholdCount,UnhealthyThr:UnhealthyThresholdCount,Path:HealthCheckPath,Matcher:Matcher}' \
  --output table

# Baseline targets
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{id:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason,desc:TargetHealth.Description}' \
  --output table

```

What will happen?

- After how many seconds can a new instance **in principle** become `healthy`?
    - Rough estimate: at least `Interval * HealthyThreshold` after the service is actually responding.
- If ASG grace period is less than that time, what happens?
    - targets stay `initial/unhealthy`
    - ASG starts replacing instances
    - ALB may remain “without healthy targets” longer than usual

Inject failure: decrease `HealthCheckGracePeriod`

```bash
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --health-check-grace-period 30

# Verify:
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].HealthCheckGracePeriod' \
  --output text
```

Trigger (force ASG to launch a new instance)

```bash
# Start instance refresh (rolling)
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":60}'

# Check refresh status (%)
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --query 'InstanceRefreshes[0].{Status:Status,Percentage:PercentageComplete,StartTime:StartTime,StatusReason:StatusReason}' \
  --output table

```

Observe

```bash
# Scaling activities (look for churn)
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "$ASG_NAME" \
  --query 'Activities[].{Time:StartTime,Status:StatusCode,Desc:Description,Cause:Cause}' \
  --output table

# Target health (look for flapping + reasons)
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{id:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason,desc:TargetHealth.Description}' \
  --output table

```

### CloudWatch (where to look)

- `HealthyHostCount` may dip
- `HTTPCode_ELB_5XX_Count` rises if healthy becomes 0

---

## D) Traffic Control Features

### D1) Deregistration Delay

### What it is

When a target leaves (scale‑in, refresh, manual deregister), ALB:

- **stops sending new requests** to the target
- but **does not cut off** in‑flight connections/requests
- waits `deregistration_delay` seconds, then removes the target

**Why:** so long requests do not break during deploys.

Target Group has an attribute:

```bash
# Current delay value
aws elbv2 describe-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --query 'Attributes[?Key==`deregistration_delay.timeout_seconds`].Value' \
  --output text

# Other important attributes
aws elbv2 describe-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --query 'Attributes[].{Key:Key,Value:Value}' \
  --output table
```

What will happen?

- If a request lasts **10 seconds** and delay = **5**, what happens? → on target exit it will likely **break**.
- If delay = **30**, requests up to 10 seconds usually survive “draining”.

Goal of D1 is **not “prove by logs”**, but:

1. see `draining`
2. connect it to scale‑in/refresh
3. understand how delay changes the draining window

```bash
# Set delay=10
aws elbv2 modify-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --attributes Key=deregistration_delay.timeout_seconds,Value=10

# Verify:
aws elbv2 describe-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --query 'Attributes[?Key==`deregistration_delay.timeout_seconds`].Value' \
  --output text

```

Trigger (force ASG to launch a new instance)

```bash
# Instance refresh
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":60}'

```

Observe

```bash
# Target health — catch draining
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{id:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason,desc:TargetHealth.Description}' \
  --output table

```

**What you should see:**

- one target goes `draining`
- after ~**10 seconds** (if delay=10) it disappears / becomes unused

ASG activities — confirm why it left

```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "$ASG_NAME" \
  --query 'Activities[].{Time:StartTime,Status:StatusCode,Desc:Description,Cause:Cause}' \
  --output table

```

Repeat with delay=120 (and compare)

```bash
aws elbv2 modify-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --attributes Key=deregistration_delay.timeout_seconds,Value=120
```

## Conclusions

- `deregistration_delay` is **insurance against errors on target exit**, but it **slows capacity release**.
- Too small delay → “sometimes 502 during deploy/scale‑in”.
- Too large delay → slow scale‑in, instances “linger” longer.

---

### D2) Slow Start

Slow start lets ALB **gradually** ramp traffic to **new healthy targets** over N seconds.

### Why

- cold caches
- JVM warmup
- heavy init → even if the health check is green, the service can still be “fragile”.

### What to observe

- without slow start: a new instance instantly gets normal traffic → risk of latency/5xx spikes
- with slow start: load ramps in gradually → more stable

```bash
aws elbv2 describe-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --query 'Attributes[?Key==`slow_start.duration_seconds`].Value' \
  --output text
```

The exact TG attribute is `slow_start.duration_seconds`.

Set it explicitly:

```bash
# Enable slow start (example: 60 seconds)
aws elbv2 modify-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --attributes Key=slow_start.duration_seconds,Value=60

# Disable slow start (0 = off)
aws elbv2 modify-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --attributes Key=slow_start.duration_seconds,Value=0

# Verify
aws elbv2 describe-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --query 'Attributes[?Key==`slow_start.duration_seconds`].Value' \
  --output text
```

### Experiment — Slow Start vs No Slow Start

Goal: compare a refresh with slow start **disabled** vs **enabled** under light load.

1) Baseline (slow start OFF):

```bash
aws elbv2 modify-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --attributes Key=slow_start.duration_seconds,Value=0

aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":60}'
```

Observe:
- `TargetResponseTime` spike right after new targets become healthy
- brief 5xx if new targets are fragile under immediate load

2) With slow start ON (e.g., 60s):

```bash
aws elbv2 modify-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --attributes Key=slow_start.duration_seconds,Value=60

aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":60}'
```

Observe:
- smoother `TargetResponseTime`
- fewer or no 5xx spikes during the first minute of traffic to new targets

Cleanup: set slow start back to your baseline (often 0 or 60).


## Acceptance

- [ ] You saw `draining` and linked it to replacement/scale‑in
- [ ] You compared delay=10 vs delay=120 and understood “why requests sometimes break”
- [ ] You validated slow start and know when it is needed

---

## Micro-drill: Drain under load (0s)

### Safety rules

- **Do not touch nginx**, no SSH.
- Light load (short burst) to avoid DoS on yourself.
- At the end, **restore delay** (usually 300).

```bash
# Prepare 3 variables
export TG_ARN="..."
export ASG_NAME="..."
export ALB_DNS="..."
```

Terminal A — **shooter** (SSM session on one web instance)

```bash
ID="$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --query 'TargetHealthDescriptions[0].Target.Id' --output text)"
aws ssm start-session --target "$ID"

# Check ALB reachability (ALB is internal):
curl -I "http://$ALB_DNS/" | head

# Simple loop
for i in $(seq 1 200); do
  curl -s -o /dev/null -w "code=%{http_code} time=%{time_total}\n" \
    "http://$ALB_DNS/"
done | awk '{c[$1]++; t+=$2; n++} END{print "----"; for(k in c) print k,c[k]; if(n) print "avg_time",t/n}'
# curl -sS -o /dev/null -w "code=%{http_code} time=%{time_total}\n" "http://$ALB_DNS/"

```

Terminal B — observer

```bash
# Save current delay
BASE_DELAY="$(aws elbv2 describe-target-group-attributes --target-group-arn "$TG_ARN" \
  --query 'Attributes[?Key==`deregistration_delay.timeout_seconds`].Value' --output text)"
echo "$BASE_DELAY"

# Set delay=0:
aws elbv2 modify-target-group-attributes --target-group-arn "$TG_ARN" \
  --attributes Key=deregistration_delay.timeout_seconds,Value=0

# Start refresh:
aws autoscaling start-instance-refresh --auto-scaling-group-name "$ASG_NAME" \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":60}'

# Monitor targets in parallel
watch -n 5 'aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query "TargetHealthDescriptions[].{id:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason}" --output table'

```

Terminal A — run the loop during the refresh

```bash
for i in $(seq 1 200); do
  curl -s -o /dev/null -w "code=%{http_code} time=%{time_total}\n" \
    "http://$ALB_DNS/"
done | awk '{c[$1]++; t+=$2; n++} END{print "----"; for(k in c) print k,c[k]; if(n) print "avg_time",t/n}'
```

Cleanup

```bash
aws elbv2 modify-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --attributes Key=deregistration_delay.timeout_seconds,Value="$BASE_DELAY"

# Verify
aws elbv2 describe-target-group-attributes \
  --target-group-arn "$TG_ARN" \
  --query 'Attributes[?Key==`deregistration_delay.timeout_seconds`].Value' \
  --output text

```

---

## 5 metrics that solve problems (AWS/ApplicationELB)

Look at **TargetGroup**, not only the LB:

1. `HealthyHostCount` — **Minimum**
2. `UnHealthyHostCount` — Maximum
3. `TargetResponseTime` + `RequestCount`
4. `HTTPCode_ELB_5XX_Count`
5. `HTTPCode_Target_5XX_Count`

**Interpretation:**

- **ELB 5XX ↑ + HealthyHostCount(min)=0** → no healthy targets / routing / TG mismatch
- **ELB 5XX ↑ + HealthyHostCount(min)>0** → timeouts / reset / capacity / app instability
- **TargetResponseTime ↑, 5XX = 0** → “green ALB” + slow → perf/dependencies/load
- **Target 5XX ↑, ELB 5XX not ↑** → app returns 500 sometimes, ALB proxies honestly

---

### Key failure modes

- Wrong health check `path` / `matcher` → all targets go unhealthy even if instances are fine.
- Slow responses / too strict `timeout` → health checks fail or users complain while ALB still looks green.
- Boot race (grace/warmup too low) → flapping/churn during launches/refresh.
- Too low `deregistration_delay` → short 502/503 spikes during scale‑in/refresh.
- Missing `slow_start` → new targets are “healthy” but fragile under immediate load.

---

## Summary

- ALB is the **judge** of target health; ASG may **act** on it (replace/refresh), but ALB decides who gets traffic.
- Health is **not binary**: targets move through `initial → healthy → draining/unhealthy/unused`.
- “ALB green” ≠ “users happy”: latency can be bad while health checks still pass.
- During refresh/scale‑in, traffic loss is usually about **deregistration delay / warmup / thresholds**, not “mystical AWS bugs”.
- Verified target state transitions with:
    - `aws elbv2 describe-target-health` (state/reason/description)
    - CloudWatch **AWS/ApplicationELB** metrics, focusing on **HealthyHostCount (Minimum)**
- Demonstrated controlled degradation during refresh:
    - `HealthyHostCount(min)` dipped to **1** and returned to **2** without “dead” targets → expected rolling behavior.
- Confirmed internal ALB reachability by generating traffic **from inside VPC** via SSM.
