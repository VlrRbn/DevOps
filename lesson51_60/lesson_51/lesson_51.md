# lesson_51

---

# ASG Scaling Policies & Instance Refresh

**Date:** 2025-01-29

**Topic:** Turn a static Auto Scaling Group into a **reactive, self-healing system**

using **scaling policies, CloudWatch alarms, and instance refresh**.

> lesson_50 taught replacement.
> 
> 
> lesson_51 teaches **reaction and controlled change**.
> 

---

## Why This Matters

Without scaling policies:

- ASG is just a “fixed replica set”
- traffic spikes = risk
- idle time = wasted money

Without instance refresh:

- AMI updates are manual
- rollouts are risky
- humans stay in the loop (bad)

**Production ASG must:**

- react to load
- replace instances safely
- roll forward without downtime

---

## Architecture

```
           ┌──────────────┐
           │ CloudWatch   │
           │  Metrics     │
           └──────┬───────┘
                  │
        ┌─────────▼─────────┐
        │ Scaling Policies  │
        │  - target tracking│
        │  - step scaling   │
        └─────────┬─────────┘
                  │
        ┌─────────▼─────────┐
        │ Auto Scaling Group│
        │ min=2 desired=2  │
        │ max=4            │
        └─────────┬─────────┘
                  │
        ┌─────────▼─────────┐
        │ Launch Template   │
        │ (baked AMI)       │
        └─────────┬─────────┘
                  │
              ┌───▼───┐
              │  ALB  │
              └───────┘

```

---

## Goals / Acceptance Criteria

- [ ]  ASG scales **out** under load
- [ ]  ASG scales **in** after cooldown
- [ ]  Scaling decisions are visible in CloudWatch
- [ ]  Instance refresh replaces instances **gradually**
- [ ]  ALB remains healthy during refresh
- [ ]  No manual instance management

---

## Preconditions

From lesson_50 must already have:

- Launch Template using baked AMI
- ASG attached to ALB Target Group
- IMDSv2 enforced
- No `aws_instance` resources
- If `enable_ssm_vpc_endpoints=false`, NAT must be enabled or SSM will not work

---

## A) Target Tracking Scaling (Core)

### Why Target Tracking

This is the **default production choice**:

- simple
- predictable
- AWS manages math for you

Example:

> “Keep average CPU at ~50%”
> 

In production, you **don’t know in advance**:

- how much traffic you’ll get
- how it will distribute
- how many instances are “enough”

Target tracking is **pressure control**, not a fixed instance count.

---

### Terraform: Target Tracking Policy

```hcl
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${var.project_name}-web-cpu-target-policy"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration { # SLA: keep average CPU around 50%
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50.0
  }

}
```

The ASG will:

- add instances when pressure increases
- remove instances when they’re idle
- do it *gradually*, with hysteresis

## Key mental model

> The ASG doesn’t think “I need 3 instances.”
> 
> 
> **The ASG thinks “pressure is above the target.”**
> 

And he:

1. Looks at **average CPU**
2. Compares it to the target
3. Decides whether to:
    - scale out
    - scale in
    - wait

You **don’t control the count**.

You **control the behavior**.

That’s what an **autonomous system** is.

---

## What AWS creates, and where to look

After `terraform apply`, AWS will automatically create **Target Tracking alarms** for the policy.
You do not need to define your own CloudWatch alarms for Target Tracking.

### Where to verify (mandatory)

**EC2 → Auto Scaling Groups → *ASG* → “Automatic scaling” tab**

Check:

- **Policy type:** Target tracking scaling
- **Target:** Average CPU = **50%**

**CloudWatch → Metrics → All metrics → AutoScaling**

Look at:

- `GroupDesiredCapacity`
- `GroupInServiceInstances`
- `CPUUtilization`

**EC2 → Auto Scaling Groups → *ASG* → Activity**

That’s where the truth is — not guesses.

Note: Target Tracking creates **service-managed CloudWatch alarms** automatically.
You usually won’t create or manage those alarms yourself.

## Mini checklist

- [ ]  EC2 → Auto Scaling Groups → **does the name match?**
- [ ]  **Automatic scaling** tab → is the policy there?
- [ ]  CloudWatch → Metrics → **AutoScaling**
- [ ]  Activity history → do you see events?

---

## B) Step & Scheduled Scaling (Control & Cost) — why, when, and how not to break it

## Important

> Target tracking = the system’s baseline behavior
> 
> 
> **Step / Scheduled = an override for special cases**
> 

This is **not** a replacement for target tracking.
Do **not** enable both Target Tracking and Step Scaling at the same time unless you really know what you're doing.

This is **not** “let’s add more policies.”

This is **intentional control**.

### 1. Step Scaling (reaction-based)

Used when:

- sharp, short spikes (marketing blasts, cron jobs, batch workloads)
- the key metric isn’t CPU (queue depth, 5xx rate, latency)
- you need to react **faster** than target tracking

### CloudWatch Alarm

```hcl
# CloudWatch alarm for high CPU (over 70% for 2 consecutive periods).
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-web-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70.0

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  alarm_description = "Alarm when CPU exceeds 70%"

  alarm_actions = [aws_autoscaling_policy.scale_out_step.arn]

}

# CloudWatch alarm for low CPU (below 30% for 5 consecutive periods).
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-web-cpu-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 30.0

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  alarm_description = "Alarm when CPU drops below 30%"

  alarm_actions = [aws_autoscaling_policy.scale_in_step.arn]

}
```

### Step Policy ([docs.aws.amazon.com](https://docs.aws.amazon.com/autoscaling/ec2/APIReference/API_PutScalingPolicy.html))

```hcl
# Auto Scaling policy (step scaling) to add 1 instance on high CPU alarm.
resource "aws_autoscaling_policy" "scale_out_step" {
  name                   = "${var.project_name}-web-scale-out-step"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "StepScaling"

  adjustment_type           = "ChangeInCapacity"
  estimated_instance_warmup = 180

  step_adjustment {
    metric_interval_lower_bound = 0
    scaling_adjustment          = 1
  }
  
}

# Auto Scaling policy (step scaling) to remove 1 instance on low CPU alarm.
resource "aws_autoscaling_policy" "scale_in_step" {
  name                   = "${var.project_name}-web-scale-in-step"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "StepScaling"

  adjustment_type           = "ChangeInCapacity"
  estimated_instance_warmup = 180

  step_adjustment {
    metric_interval_upper_bound = 0
    scaling_adjustment          = -1
  }
  
}
```

---

### 2. Scheduled Scaling (cost discipline)

### When it actually makes sense

- predictable time-based traffic
- business hours
- nights = near-zero load

Target tracking **doesn’t know about time**. It only knows about load.

```hcl
# Scheduled action to scale down at 22:00 UTC (Ireland local time).
resource "aws_autoscaling_schedule" "scale_down_night" {
  scheduled_action_name  = "${var.project_name}-web-scale-down-night"
  autoscaling_group_name = aws_autoscaling_group.web.name
  desired_capacity       = 1
  min_size               = 1
  max_size               = 2
  start_time             = "2026-01-30T22:00:00Z"
  end_time               = "2027-12-31T06:00:00Z"
  recurrence             = "0 22 * * *" # Every day at 22:00 UTC (Ireland local time)
  
}
```

---

## C) Instance Refresh (Safe Rollouts)

### Why Instance Refresh exists

Without it:

- changing the AMI does nothing immediately (in an ASG, the **Launch Template applies only to NEW instances**)
- you wait for natural termination
- rollouts are random (you end up with a **mixed-version** group)

With it:

- controlled replacement
- reproducible behavior
- zero downtime is possible

Why “possible” and not “guaranteed”?

Because zero downtime depends on:

- **health checks** (ALB/ASG)
- **warmup**
- **min healthy percentage**
- your application behavior (stateless / readiness)

---

### Terraform: Instance Refresh

```hcl
resource "aws_autoscaling_group" "web" {
  # ... existing config ...
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 180
    }
    triggers = ["launch_template"]
  }
}

```

**Key insight:**

Note: With `min_healthy_percentage = 50` and `desired = 2`,
the ASG may temporarily run with a single healthy instance during refresh.
This is fine for a lab but not for strict no-downtime production.

> Updating the Launch Template version triggers an instance refresh automatically.
> 

So you get an **immutable deployment** via:

- bake a new AMI
- update the Launch Template
- `apply`
- the ASG rolls it out automatically

```hcl
aws autoscaling describe-instance-refreshes --auto-scaling-group-name <asg-name>

```

Check the fields:

- `Status`: Pending / InProgress / Successful / Failed / Cancelling
- `PercentageComplete`

---

## D) Drills

---

## Common Pitfalls

- Internal ALB does **not** resolve outside the VPC. Use SSM port forwarding or run tests inside the VPC.
- Load test too weak → CPU stays low → no scale-out. Use longer tests (`-t`) or heavier endpoints.
- Target Tracking and Step Scaling enabled together can conflict and cause noisy scaling.
- `enable_ssm_vpc_endpoints=false` without NAT → SSM will not work.
- `min_healthy_percentage=50` with `desired=2` means only 1 instance may stay healthy during refresh.
- CloudWatch metrics can lag by 1–3 minutes; scaling is not instant.

### Drill 1 — Load Spike

**Goal:** Observe automatic scale-out.

### What we need in place beforehand

**Where:** AWS Console or CLI

- ASG: `min=2 desired=2 max=4`
- The ASG is attached to the ALB **Target Group**
- Target Group: **2 healthy targets**
- A target tracking policy (CPU target ~50) **is configured**

From inside VPC (proxy or web):

```bash
sudo apt update
sudo apt install -y apache2-utils
ab -V

ab -t 300 -c 200 http://<internal-alb-dns>/
```

Note: Internal ALB DNS does **not** resolve outside the VPC.
Use SSM port forwarding if you run the test locally.

Test `ab` locally via SSM port forwarding to the `ssm-proxy`.

```bash
aws ssm start-session \
  --target <ssm_proxy_instance_id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<internal-alb-dns>"],"portNumber":["80"],"localPortNumber":["8080"]}'
  
ab -t 300 -c 200 http://127.0.0.1:8080/

```

Temporarily run `stress` on the web instances via SSM.

```bash
aws ssm start-session --target <web_instance_id>

# inside:
sudo apt update -y
sudo apt install -y stress
stress --cpu 2 --timeout 300

```

Observe:

- DesiredCapacity increases
- New instances launch
- ALB stays healthy

1. **CPUUtilization ↑** (CloudWatch)
2. **ASG DesiredCapacity ↑** (decision)
3. **ASG Activity: Launching instance**
4. **Target Group: new target → initial → healthy**
5. **GroupInServiceInstances ↑ to 3**

**Acceptance:**

- [ ]  `DesiredCapacity` increased on its own
- [ ]  a new instance appeared in the ASG Activity history
- [ ]  the Target Group shows 3 healthy (or 2 healthy + 1 initial → then 3 healthy)
- [ ]  the ALB never went into an “all targets unhealthy” state
- [ ]  there was no Terraform apply and no manual termination

---

### Drill 2 — Cooldown & Scale-In

## Goal

Prove that the system can **automatically**:

- detect that the load is gone
- **wait** for cooldown / warmup
- **scale in safely**
- **not go below** the minimum size

1. Stop load
2. Wait 5–10 minutes
3. Observe scale-in

**Acceptance:**

- [ ]  Scale-in happened **automatically**
- [ ]  `DesiredCapacity` returned to `min_size`
- [ ]  Exactly **one** instance was terminated
- [ ]  No manual actions were taken
- [ ]  The ALB stayed healthy

---

## What happened

After **Drill 1 (scale-out)**:

- the load went away
- CPU/pressure dropped
- target tracking saw that the target was no longer being exceeded
- target tracking saw pressure drop and scaled in
- the ASG automatically:
    - waited for the cooldown
    - selected **one** instance
    - terminated it cleanly
    - returned to `min_size = 2`

---

### Drill 3 — AMI Rolling Update

1. Bake new AMI (lesson_49)
2. Update `web_ami_id`
3. `terraform apply`
4. Watch:
    - Instance refresh status
    - Gradual replacement
    - ALB health

CLI:

```bash
aws autoscaling describe-instance-refreshes --auto-scaling-group-name <asg-name>

```

**Acceptance:**

- [ ]  Instance refresh started **automatically**
- [ ]  Instances were replaced **one by one**
- [ ]  ALB always had healthy targets
- [ ]  New version actually serves traffic
- [ ]  No SSH or manual intervention

---

## Common Pitfalls

- Using both target tracking and step scaling without understanding priority
- Forgetting cooldown / warmup
- Expecting instant scale-in
- Debugging ASG by SSH
- Treating instance refresh as “deploy button”

---

## Security Checklist

- IMDSv2 required
- No SSH access
- No secrets in AMI
- Scaling driven by metrics, not humans
- Rollouts are automated and observable

---

## Summary

- Lesson focus: turn a static ASG into an **autonomous system** that reacts to load and updates safely.
- Core mechanism: **Target Tracking** (CPU ~50%) for scale‑out/scale‑in without manual instance counting.
- **Step/Scheduled scaling** are overrides, not defaults; don’t run them together with Target Tracking.
- **Instance Refresh** enables controlled rollouts when the Launch Template/AMI changes.
- Drill validation path: **CPU ↑ → DesiredCapacity ↑ → Activity (launch) → Target Group healthy → InService**.
- Common pitfalls: internal ALB not resolvable outside VPC, weak load tests, CloudWatch lag.
