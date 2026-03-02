# lesson_57

---

# Deployment Quality Gates (Load, Latency, SLO-Style Release Rules)

**Date:** 2026-03-01

**Focus:** move from “rollout completed” to “rollout met quality” by adding release gates on latency and error behavior.

**Mindset:** ship by evidence.

## Deployment Models Map

This lesson continues the same branch as lessons 55-56.

| Model | Main idea | Strength | Cost/Complexity | Best use |
|---|---|---|---|---|
| Blue/Green | two fleets, traffic switch | fastest rollback | higher cost | safest cutover |
| Rolling Refresh | one fleet, gradual replacement | cheaper/simple | weaker rollback | small/medium services |
| Canary / Weighted | small % first, then expand | best risk control | most operational thinking | high-risk releases |

- lesson 55: deployment engine (`Instance Refresh`)
- lesson 56: safety guardrails (`auto rollback`, checkpoints, alarm-gates)
- **lesson 57**: quality gates (latency + errors under controlled load)

---

## Why This Lesson Exists

A deployment can be “successful” and still bad for users:

- latency rises significantly
- error budget is degraded without immediate crash
- capacity looks fine, but response quality regresses

Quality gates answer one operator question at checkpoint:

> “Do we continue rollout, or roll back now?”

---

## Quick Path (20–30 min)

1. Confirm baseline alarms are `OK`.
2. Add two release alarms in Terraform: release target 5xx + release latency.
3. Apply Terraform and verify alarm states.
4. Build `57-02` AMI and update `web_ami_id`.
5. Start rollout (`terraform apply`).
6. At checkpoint mode (`[50]`), run 5-minute canary load.
7. Make Go/No-Go decision by gate rules.
8. Complete rollout to 100% or roll back to known-good.

---

## Target Architecture

```text
Proxy load tool -> ALB -> TG -> ASG (Instance Refresh + checkpoint)
                     |
                     +-> CloudWatch metrics
                     +-> Safety alarms (lesson 56)
                     +-> Quality alarms (lesson 57)
```

Important split:

- **Safety alarms:** protect platform health and rollback fast on clear breakage.
- **Quality alarms:** protect user experience and release quality.

---

## Inputs (copy/paste first)

Run from:

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs
```

Set variables:

```bash
export ASG_NAME="$(terraform output -raw web_asg_name)"
export TG_ARN="$(terraform output -raw web_tg_arn)"
export ALB_DNS="$(terraform output -raw alb_dns_name)"
export PROJECT="$(terraform output -raw web_asg_name | sed 's/-web-asg$//')"
printf "ASG=%s\nTG=%s\nALB=%s\nPROJECT=%s\n" "$ASG_NAME" "$TG_ARN" "$ALB_DNS" "$PROJECT"
```

Open proxy session (for internal ALB checks/load):

```bash
aws ssm start-session --target "$(terraform output -raw ssm_proxy_instance_id)"
```

Inside proxy session:

```bash
ALB="http://$ALB_DNS"
```

---

## Goals / Acceptance Criteria

- [ ] Two quality gates are defined and observable (`release-target-5xx`, `release-latency`)
- [ ] A standardized canary load profile is used at checkpoint
- [ ] Continue/Rollback decision is made from metrics + alarms only
- [ ] Decision and outcome are proven via proof pack outputs

---

## Preconditions

- lesson 56 baseline works (refresh, checkpoint logic, rollback path)
- response body includes `BUILD_ID` / host identity
- ALB reachable through SSM proxy
- Terraform + Packer + AWS CLI configured

Hard rule: no “manual fix on instance” during decision phase.

---

## A) Define Quality Gates

### Gate 1: release error gate (hard stop)

Signal:

- `HTTPCode_Target_5XX_Count`

Rule:

- sustained non-trivial 5xx during canary => rollback.

Example threshold for lab:

- `threshold = 2`, `period = 60`, `evaluation_periods = 2`

### Gate 2: release latency gate (quality stop)

Signal:

- `TargetResponseTime` (Average)

Rule:

- if sustained latency exceeds threshold during canary window => rollback or hold.

Lab threshold:

- `threshold = 0.5` seconds
- `period = 60`
- `evaluation_periods = 5`

### Canary window standard

Keep test conditions fixed:

- duration: 5 minutes
- same endpoint
- same concurrency/threads
- same proxy host

If load shape changes, gate decision is invalid.

---

## B) Add Release Gate Alarms in Terraform

Edit:

`lessons/57-deployment-quality-gates/lab_57/terraform/modules/network/monitoring.tf`

Add two alarms:

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

Apply:

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs
terraform fmt -recursive
terraform plan
terraform apply
```

Verify:

```bash
aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT}-release-target-5xx" "${PROJECT}-release-latency" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName,Threshold]' \
  --output table
```

---

## C) Safety vs Quality Wiring

Recommendation:

- keep lesson 56 **safety alarms** in ASG `alarm_specification` (hard protection)
- use lesson 57 **quality alarms** for Go/No-Go at checkpoint (operator decision)

Reason:

- safety rollback must stay deterministic and low-noise
- quality gates are stricter and may be context-sensitive

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

Expected: all alarms `OK`, targets healthy.

Optional: build dedicated proxy AMI with `wrk` (no NAT needed at runtime)

```bash
cd lessons/57-deployment-quality-gates/lab_57/packer/ssm_proxy
packer build -var 'build_id=57-wrk' .
```

Set resulting AMI in `ssm_proxy_ami_id` (`terraform.tfvars`), then:

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs
terraform plan
terraform apply
```

### Step 1. Baseline load on current build

Use one fixed profile and keep it identical between baseline and canary.

Default (works without NAT, no package install required):

```bash
log="/tmp/l57_baseline_$(date +%Y%m%d_%H%M%S).log"
end=$(( $(date +%s) + 180 )) # 3 minutes
while [ "$(date +%s)" -lt "$end" ]; do
  seq 1 80 | xargs -n1 -P20 -I{} \
    curl -s -o /dev/null -w "%{http_code} %{time_total}\n" "$ALB/"
done >> "$log"

awk '$1 ~ /^2/ {ok++; t+=$2} $1 !~ /^2/ {bad++}
END {total=ok+bad; printf "baseline total=%d ok=%d bad=%d avg=%.3fs\n", total, ok, bad, (ok?t/ok:0)}' "$log"
```

Optional (`wrk` or `ab`) if already installed or NAT is available:

```bash
# wrk example
wrk -t4 -c80 -d180s "$ALB/"

# ab example
ab -t 180 -c 80 "$ALB/"
```

### Step 2. Deploy new build

```bash
cd lessons/57-deployment-quality-gates/lab_57/packer/web
packer build -var 'build_id=57-02' .
```

Set new AMI in `terraform.tfvars`, then:

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs
terraform plan
terraform apply
```

### Step 3. Checkpoint canary test

If you train checkpoint operation, use `checkpoint_percentages = [50]` in ASG preferences.

At checkpoint:

```bash
log="/tmp/l57_canary_$(date +%Y%m%d_%H%M%S).log"
end=$(( $(date +%s) + 300 )) # 5 minutes
while [ "$(date +%s)" -lt "$end" ]; do
  seq 1 80 | xargs -n1 -P20 -I{} \
    curl -s -o /dev/null -w "%{http_code} %{time_total}\n" "$ALB/"
done >> "$log"

awk '$1 ~ /^2/ {ok++; t+=$2} $1 !~ /^2/ {bad++}
END {total=ok+bad; printf "canary total=%d ok=%d bad=%d avg=%.3fs\n", total, ok, bad, (ok?t/ok:0)}' "$log"
```

Optional if available:

```bash
wrk -t4 -c80 -d300s "$ALB/"
```

In parallel from local shell:

```bash
watch -n 15 "aws cloudwatch describe-alarms \
  --alarm-names '${PROJECT}-release-target-5xx' '${PROJECT}-release-latency' \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
  --output table"
```

### Step 4. Decision rules

Continue only if all are true:

- release alarms remain `OK`
- safety alarms remain `OK`
- target health remains stable
- sampler shows mixed/advancing rollout without failure signs

Rollback if any gate fails.

Decision matrix:

| Observation | Decision |
|---|---|
| Safety alarms `OK`, quality alarms `OK`, target health stable | **GO** (continue rollout) |
| Safety alarms `OK`, but quality alarms are flapping/near threshold | **HOLD** (extend canary, re-check) |
| Any safety alarm in `ALARM` or clear target health degradation | **ROLLBACK** |
| Quality alarms persist in `ALARM` under fixed canary profile | **ROLLBACK** |

---

## E) Build Sampler / Evidence Commands

Detailed collection guide: `lessons/57-deployment-quality-gates/proof-pack.en.md`.

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

1. Run baseline load (3 min).
2. Deploy `57-02` and reach checkpoint mode.
3. Run canary load (5 min).
4. All alarms remain `OK`.
5. Continue rollout to 100%.

Success criteria:

- [ ] no release gate alarm fired
- [ ] no safety alarm fired
- [ ] end state mostly/all `BUILD=57-02`

---

## Drill 2 — Forced latency gate failure (mechanics drill)

Purpose: validate gate behavior without breaking fleet.

Method (lab-safe): temporarily lower latency threshold to a strict value (e.g. `0.05`) for `release-latency`, apply, run same canary load.

Expected:

- `release-latency` goes `ALARM`
- decision = rollback/hold

Then revert threshold to normal (`0.5`) and apply.

Success criteria:

- [ ] latency gate transition observed and proven
- [ ] rollback/hold decision documented from evidence

---

## Drill 3 — Error regression (`57-bad`) with rollback

Use intentionally broken AMI path (same pattern as lesson 56):

```bash
cd lessons/57-deployment-quality-gates/lab_57/packer/web
packer build -var 'build_id=57-bad' .
```

Deploy `57-bad`, run canary load, observe gate/alarm reaction, rollback to known-good AMI.

Success criteria:

- [ ] 5xx-related signal caused rollback decision
- [ ] final state returns to known-good build

---

## Drill 4 — Write team-ready Go/No-Go rules (5 lines)

Write and save local rules:

1. If `release-target-5xx` = `ALARM` -> rollback now.
2. If `release-latency` = `ALARM` for full evaluation window -> rollback/hold.
3. If safety alarms fail (`target-5xx-critical`, `alb-unhealthy`) -> rollback now.
4. If alarms are clean and target health stable -> continue.
5. Every decision must have proof pack output attached.

Success criteria:

- [ ] you can make a release call without SSHing into instances

---

## G) Pitfalls

- changing load shape between baseline and canary
- mixing safety and quality alarms blindly in auto rollback
- reading CPU only and ignoring ALB metrics
- skipping proof artifacts after decision
- not restoring temporary test thresholds

---

## Final Acceptance

- [ ] release quality alarms implemented and validated
- [ ] canary decision process executed from metrics
- [ ] rollback path validated for quality failure and error failure
- [ ] proof pack collected and attached
- [ ] runbook reusable for next deployment lesson

---

## Security Checklist

- [ ] no SSH introduced into release workflow
- [ ] IMDSv2 remains required in Launch Template
- [ ] no secrets baked in AMI
- [ ] alarms map to concrete operator actions
- [ ] rollout and rollback both evidence-driven

---

## Lesson Summary

After lesson 57 you can:

- keep lesson 56 safety guardrails intact
- add quality-oriented release gates (latency + errors)
- run consistent canary checks at checkpoint
- make reproducible Go/No-Go decisions backed by evidence
