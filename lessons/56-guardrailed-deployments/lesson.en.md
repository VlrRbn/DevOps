# lesson_56

---

# Guardrailed Deployments (Auto Rollback, Checkpoints, Skip Matching)

**Date:** 2026-02-24

**Focus:** turn Instance Refresh into a safe release pipeline with:

- CloudWatch alarm gates
- auto rollback
- checkpoints
- skip matching

## Deployment Models Map

This lesson does not replace Blue/Green or Canary. It adds guardrails to the **single-fleet rolling** model from lesson 55.

| Model | Main idea | Strength | Cost/Complexity | Best use |
|---|---|---|---|---|
| Blue/Green | two fleets, traffic switch | fastest rollback | higher cost | safest cutover |
| Rolling Refresh | one fleet, gradual replacement | cheaper/simple | weaker rollback | small/medium services |
| Canary / Weighted | small % first, then expand | best risk control | most operational thinking | high-risk releases |

This lesson focuses on **guardrails for Rolling Refresh**: alarm gates, auto rollback, checkpoints, skip matching.

---

## Why This Lesson Exists

`lesson_55` taught the deployment engine:

- change AMI in Launch Template
- run refresh
- observe and rollback manually when needed

`lesson_56` adds guardrails so the platform can protect itself:

- auto rollback from alarm signals
- checkpoint stops for controlled verification
- skip matching to reduce pointless churn

This lesson is about reducing blast radius, not adding complexity.

---

## Quick Path (20–30 min)

1. Ensure alarms are `OK`.
2. Add guardrails in ASG `instance_refresh.preferences`.
3. `terraform apply`.
4. Bake `56-02` AMI and set `web_ami_id`.
5. `terraform apply` (refresh starts).
6. Observe refresh + target health + alarms.
7. Validate rollout progress continuously (`BUILD_ID`, target health, alarms).
8. Wait completion and confirm only `56-02` remains.
9. Run bad AMI drill and verify auto rollback.
10. Save proof pack outputs.

---

## Target Architecture

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

For checkpoint training mode, temporarily switch `checkpoint_percentages` to `[50]`.

---

## Inputs (copy/paste first)

Run from:

```bash
cd lessons/56-guardrailed-deployments/lab_56/terraform/envs
```

Set working variables once:

```bash
export ASG_NAME="$(terraform output -raw web_asg_name)"
export TG_ARN="$(terraform output -raw web_tg_arn)"
export ALB_DNS="$(terraform output -raw alb_dns_name)"
export PROJECT="$(terraform output -raw web_asg_name | sed 's/-web-asg$//')"
```

Open SSM proxy session (for internal ALB checks):

```bash
aws ssm start-session --target "$(terraform output -raw ssm_proxy_instance_id)"
```

Inside SSM session, paste ALB DNS:

```bash
ALB_DNS="internal-...elb.amazonaws.com"
```

Baseline snapshot (to compare later):

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table
```

and

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 3 \
  --query 'InstanceRefreshes[*].[InstanceRefreshId,Status,PercentageComplete,StartTime,EndTime,StatusReason]' \
  --output table

  # or

aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 3 \
  --query 'length(InstanceRefreshes)'
```

---

## Goals / Acceptance Criteria

- [ ] Refresh rolls out new AMI safely
- [ ] Guardrail alarms are connected to refresh
- [ ] Bad rollout triggers automatic rollback
- [ ] Checkpoint gives controlled validation window
- [ ] Skip matching reduces unnecessary replacement
- [ ] Evidence captured: refresh state, alarm states, target health, traffic sample

---

## Preconditions

- `lesson_55` baseline works end-to-end
- app response includes `BUILD_ID` (or equivalent release identity)
- ALB reachable through SSM proxy model
- Terraform + Packer + AWS CLI are working

Hard rule: no ad-hoc instance patching during rollout.

---

## A) Define Release Signals (CloudWatch Alarms)

### Signal policy

Use alarms that represent user impact/capacity impact.

Use 2 core gates for refresh rollback:

1. `HTTPCode_Target_5XX_Count` (backend errors)
2. `UnHealthyHostCount` (capacity loss)

### Why not “all possible alarms”

Too many alarms make rollback noisy and non-deterministic.
Guardrails must be strict, but predictable.

### Minimal alarm examples

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

### Verify alarms before deployment

```bash
aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT}-target-5xx-critical" "${PROJECT}-alb-unhealthy-hosts" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName,Threshold]' \
  --output table
```

Expected: both alarms are `OK` before refresh start.

---

## B) Enable Guardrails in ASG Instance Refresh

Edit:

`lessons/56-guardrailed-deployments/lab_56/terraform/modules/network/asg.tf`

Current block is minimal. Replace/extend preferences with guardrails:

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

### Why each setting exists

- `auto_rollback = true`:
  fail-safe behavior on bad health signals.
- `alarm_specification`:
  binds refresh decision to objective signals.
- `checkpoint_percentages = [100]`:
  no mid-stop; easier to finish end-to-end rollout drills.
- `checkpoint_delay`:
  used when checkpoints are enabled (for example, `[50]` training mode).
- `skip_matching = true`:
  avoids replacing already matching instances.

Checkpoint mode guidance:

- use `[100]` when you want uninterrupted rollout completion
- use `[50]` when you want an explicit human decision gate in the middle

### Apply

```bash
cd lessons/56-guardrailed-deployments/lab_56/terraform/envs
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Acceptance:

- [ ] apply succeeded
- [ ] ASG refresh preferences include guardrails

---

## C) Operational Runbook (Normal Good Rollout)

### Step 0 — Baseline snapshot

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

Expected: no active failed refresh, all targets healthy.

### Step 1 — Build next AMI

```bash
cd lessons/56-guardrailed-deployments/lab_56/packer/web
packer build -var 'build_id=56-02' .
```

Capture new AMI ID from Packer output.

### Step 2 — Update Terraform input

Edit `terraform.tfvars`:

```hcl
web_ami_id = "ami-xxxxxxxxxxxxxxxxx"
```

Then apply:

```bash
cd lessons/56-guardrailed-deployments/lab_56/terraform/envs
terraform plan
terraform apply
```

### Step 3 — Monitor refresh

```bash
watch -n 10 "aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name '$ASG_NAME' \
  --max-records 1 \
  --query 'InstanceRefreshes[0].[Status,PercentageComplete,StatusReason]' \
  --output table"
```

### Step 4 — Check alarm states in parallel

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

### Step 5 — Optional checkpoint validation mode (50%)

Current lab default is `checkpoint_percentages = [100]`, so there is no midpoint pause.
If you want to practice checkpoint operations, set `checkpoint_percentages = [50]`, apply, then run this step.

Inside SSM proxy session:

```bash
for i in {1..40}; do
  curl -s -H 'Connection: close' "http://$ALB_DNS/" | egrep -i 'BUILD|Hostname|InstanceId' || true
  sleep 1
done
```

From local terminal:

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table
```

Expected in 50% checkpoint mode:

- mixed `BUILD_ID` (`56-01` + `56-02`) is visible
- no sustained unhealthy target state
- guardrail alarms remain `OK`

### Step 6 — Completion validation

After refresh completes:

- ALB sampling returns only `56-02`
- alarms remain `OK`
- target health all `healthy`

---

## D) Drills

## Drill 1 — Good rollout with evidence

Start state:

- fleet on `56-01`
- alarms `OK`

Action:

- deploy `56-02`
- observe completion (and checkpoint only if you enable `[50]` mode)

Expected:

- mixed fleet at checkpoint (only in `[50]` mode)
- full `56-02` at end
- no rollback

Evidence:

- refresh status timeline
- alarm state timeline
- target health snapshots
- curl sampler output

Acceptance:

- [ ] all evidence collected and consistent

---

## Drill 2 — Bad AMI, automatic rollback

Goal: prove auto rollback without manual.

### Option A (clean lab method)

Build intentionally broken AMI with a `*-bad` build ID (for example `56-bad`).
The existing `disable-nginx.sh` provisioner is conditional and activates only for `build_id` values ending with `-bad`.

Path:

`lessons/56-guardrailed-deployments/lab_56/packer/web/scripts/disable-nginx.sh`

Then build and deploy as `56-bad`.

### Option B (quick but noisier)

Temporarily break app response/health behavior inside AMI bake pipeline so targets fail checks.

Run deployment as usual and observe:

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 5
```

Expected:

- one or more guardrail alarms go `ALARM`
- refresh status transitions to rollback/cancel outcome
- traffic/fleet returns to last known good AMI

1) Scaling activities (launch/terminate with causes)
```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-items 10 \
  --query 'Activities[*].[StartTime,StatusCode,Description,Cause]' \
  --output table
```

2) Which instances are currently in ASG (and which AMIs they use)
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus,LaunchTemplate.Version]' \
  --output table

# Then use the instance IDs from the table:
aws ec2 describe-instances \
  --instance-ids <id1> <id2> \
  --query 'Reservations[*].Instances[*].[InstanceId,ImageId,LaunchTime]' \
  --output table
```

3) Current refresh state (latest entries)
```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 3 \
  --query 'InstanceRefreshes[*].[InstanceRefreshId,Status,PercentageComplete,StartTime,EndTime,StatusReason]' \
  --output table
```

Acceptance:

- [ ] rollback happened automatically
- [ ] no manual cancel/terminate required

---

## Drill 3 — Checkpoint Go/No-Go decision (training mode)

Before this drill, set `checkpoint_percentages = [50]` and apply.
At checkpoint, use rule-based decision only.

### Go/No-Go matrix

| Signal | Continue | Rollback |
|---|---|---|
| `target_5xx` | transient spikes only, returns to `OK` quickly | sustained errors / alarm stays `ALARM` |
| `UnHealthyHostCount` | brief blip, recovers to zero | persistent unhealthy targets |
| ALB sample (`BUILD_ID`) | mixed fleet, no error responses | mixed fleet with visible failures |
| Refresh status reason | normal progress | recurring failure reason/churn |

Acceptance:

- [ ] decision is justified by metrics/evidence, not intuition

---

## Drill 4 — Skip matching sanity

Goal: understand churn behavior.

Action:

1. Apply a change that should not require replacement semantics for already matching instances.
2. Trigger refresh path.
3. Compare replacement count/duration with previous runs.

Expected:

- reduced unnecessary replacement when instances already match desired configuration

Important:

- skip matching is not a substitute for drift management.

Acceptance:

- [ ] you can explain when skip matching helps and when it can hide assumptions

---

## E) Proof Pack (must-have commands)

### 1) Refresh summary

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 5 \
  --query 'InstanceRefreshes[*].[InstanceRefreshId,Status,PercentageComplete,StartTime,EndTime,StatusReason]' \
  --output table
```

### 2) Alarm states

```bash
aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT}-target-5xx-critical" "${PROJECT}-alb-unhealthy-hosts" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateUpdatedTimestamp]' \
  --output table
```

### 3) Target health timeline

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason,TargetHealth.Description]' \
  --output table
```

### 4) Build identity sampling (inside proxy)

```bash
for i in {1..60}; do
  curl -s -H 'Connection: close' "http://$ALB_DNS/" | egrep -i 'BUILD|Hostname|InstanceId' || true
  sleep 1
done
```

### 5) Scaling activities (churn visibility)

```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-items 30 \
  --query 'Activities[*].[StartTime,StatusCode,Description,Cause]' \
  --output table
```

---

## F) Failure Interpretation Cheat Sheet

- Alarm `ALARM` + refresh rollback -> desired guardrail behavior
- Alarm `OK` + refresh fails -> likely warmup/grace/checkpoint tuning issue
- Frequent `UnHealthyHostCount` spikes -> investigate health endpoint stability and startup timing
- High churn with skip matching -> verify what changed in Launch Template and AMI contract

---

## G) Common Pitfalls

- Alarms too sensitive -> false rollback loops
- Alarms too loose -> rollback too late
- `checkpoint_delay` too short -> no time for meaningful validation
- build identity missing in response -> no proof, only guesses
- skip matching misunderstood as drift control

---

## Final Acceptance

- [ ] good rollout completed with checkpoint evidence
- [ ] bad rollout auto-rolled back using alarm gates
- [ ] proof pack captured and saved
- [ ] operator can explain Go/No-Go decision path in 5 lines

---

## Security Checklist

- [ ] no SSH opened for deployment workflow
- [ ] IMDSv2 enforced in Launch Template
- [ ] no secrets baked into AMI
- [ ] alarms tied to user-impact/capacity signals
- [ ] rollback path validated before rollout starts

---

## Lesson Summary

- **What you learned:** how to harden `ASG Instance Refresh` with `alarm gates`, `auto rollback`, `checkpoints`, and `skip matching`.
- **What you practiced:** a good rollout (`56-02`), a bad rollout (`56-bad`), and runtime verification via `describe-instance-refreshes`, `describe-target-health`, and `describe-alarms`.
- **Key point:** auto rollback protects runtime behavior, but it does not change Terraform desired state; after rollback you must restore `web_ami_id` to known-good.
- **Operational focus:** evidence-first decisions — `Go/No-Go` is based on metrics and refresh state, not intuition.
- **Expected outcome:** you can explain `single-fleet rolling` vs `blue/green`, complete refresh to 100%, and prove deployment outcome with a proof pack.

