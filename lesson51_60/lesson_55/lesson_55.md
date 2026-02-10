# lesson_55b

# Rolling Deployments & Safe Rollback (ASG Instance Refresh as a Deployment Engine)

**Date:** 2026-02-07

**Focus:** Use **ASG Instance Refresh** as a deployment mechanism: controlled rollouts, health gates, and deterministic rollback.

**Mindset:** Immutable infra, rebuild-not-fix, evidence-based verification.

---

## Why This Lesson Exists

lesson_54 taught a **traffic switching** (Blue/Green).

lesson_55 teaches a **shipping changes safely inside one fleet**:

- Roll out a new AMI gradually
- Observe health gates
- Abort fast when it’s broken
- Roll back by reverting the artifact (AMI) and refreshing again

> If you can’t roll back in minutes, you don’t have a deployment process — you have a gamble.
> 

---

## Target Architecture

```
Client
  |
  v
ALB ──────────> Target Group (single)
                   ^
                   |
                 ASG  (Instance Refresh)
                   ^
                   |
            Launch Template vN (AMI)
```

**Key rule:** Terraform defines the *contract*, ASG executes the rollout.

---

## Goals / Acceptance Criteria

- [ ]  You can roll out **AMI v55-02** over **v55-01** using **Instance Refresh**
- [ ]  ALB stays available (no sustained 5XX, no “all targets unhealthy”)
- [ ]  You can **abort** a refresh when targets go bad
- [ ]  You can **roll back** by reverting AMI and running refresh again
- [ ]  You can prove everything using **metrics + CLI + curl sampling** (no guessing)

---

## Preconditions

You already have:

- Internal ALB + Target Group
- Launch Template + ASG attached to TG (lesson_50)
- Scaling policies (lesson_51)
- Observability dashboard/alarms (lesson_52)
- ALB health mental model (lesson_53)
- Optional Blue/Green knowledge (lesson_54)

**Hard rule for this lesson:** no manual “fixes” on instances to “save the rollout”.

---

## A) Deployment Contract — Version Must Be Visible

### Required: response must expose build identity

Your web page must show at least:

- `BUILD_ID` (e.g., `55-01`, `55-02`)
- hostname / instance-id

**Why:** without identity, you cannot prove rollout progress.

Instance Refresh is a **gradual replacement**. Without identity markers, you cannot prove:

- that part of the fleet is already on the new AMI
- that the new version is actually serving traffic
- that rollback really returned the previous version

### Recommended implementation (AMI bake-time + boot-time render)

- Bake base page with placeholders in AMI
- At boot, a oneshot systemd service renders:
    - hostname
    - instance-id (IMDSv2)
    - build stamp baked into AMI (file inside AMI)

**Practice (quick):** For each AMI, store build id:

- `/etc/web-build/build_id`

Example: 55-01 or 55-02

How to build versions `55-01` and `55-02`:

```bash
cd lesson51_60/lesson_55/lab_55/packer/web
packer build -var 'build_id=55-01' .
packer build -var 'build_id=55-02' .
```

Checks on an instance:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=lab55" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,Role:Tags[?Key=='Role']|[0].Value,PrivIP:PrivateIpAddress,Subnet:SubnetId}" \
  --output table

cat /etc/web-build/build_id
hostname
curl -s localhost | grep -E 'BUILD_ID|Hostname|InstanceId'
sudo systemctl status nginx --no-pager
sudo journalctl -u nginx -n 50 --no-pager
```

Via ALB sampler

```bash
cd lesson51_60/lesson_55/lab_55/terraform/envs
ALB_DNS="$(terraform output -raw alb_dns_name)"
echo "$ALB_DNS"
aws ssm start-session --target "$(terraform output -raw ssm_proxy_instance_id)"
```

Inside SSM session:

```bash
# paste value from local terminal output above
# example: ALB_DNS="internal-lab55-app-alb-xxxx.eu-west-1.elb.amazonaws.com"
for i in {1..30}; do
  curl -s -H 'Connection: close' "http://$ALB_DNS/" | grep -E 'BUILD|Hostname|InstanceId' || true
done
```

**Acceptance:**

- [ ]  Response consistently shows `BUILD=55-01`
- [ ]  Hostname/instance-id is visible
- [ ]  nginx is active, logs have no suspicious errors

---

## B) Terraform — Instance Refresh as a Deployment Engine

### 1) Ensure Launch Template versioning is meaningful

**Launch Template** should:

- use `image_id = var.web_ami_id`
- enforce IMDSv2
- minimal user-data only or without it

**WHAT** — `image_id` must come from `var.web_ami_id`. Change AMI -> change contract -> ASG understands that refresh is needed.

**WHY** — this makes deployment **deterministic**:

- artifact = AMI
- deployment = artifact change in LT
- rollback = revert to previous AMI in LT

If `image_id` is hardcoded or changed manually, you lose deployment control.

**WHAT** — keep `user-data` minimal or empty.

**WHY** — any heavy startup logic turns rollout into a lottery:

- network not ready -> user-data fails -> health drops -> refresh churn
- package repository slowdown -> rollout starts flapping

If you only need to render a few runtime fields (hostname/instance-id), use a **oneshot systemd** service plus a small script (not heavy user-data).

Example (conceptual):

```hcl
resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = var.web_ami_id
  instance_type = var.instance_type_web

  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = base64encode(file("${path.module}/user-data-minimal.sh"))

  metadata_options {
    http_tokens = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name   = "${var.project_name}-web"
      Role   = "web"
      Lesson = "55"
    }
  }
}
----------------------------------------------------------------------
# This is how look in my lab_55
resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = var.web_ami_id
  instance_type = var.instance_type_web
  update_default_version = true

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.web.id]
  }

  dynamic "iam_instance_profile" {
    for_each = var.enable_web_ssm ? [1] : []
    content {
      name = aws_iam_instance_profile.ec2_ssm_instance_profile.name
    }

  }

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.tags, {
      Name  = "${var.project_name}-web"
      Role  = "web"
      Fleet = "primary"
    })
  }
}
```

### 2) ASG Instance Refresh

**WHAT** — with `health_check_type = ELB`, ASG considers an instance healthy only when ALB/TG health is healthy.

**WHY** — otherwise you get a classic production failure pattern:

- EC2 is `running`,
- target group is `unhealthy`,
- rollout continues and drains fleet health.

`grace_period` gives new instances time to boot before ASG starts replacing them aggressively.

WHAT — `strategy = "Rolling"` replaces instances gradually.

WHY — preserves availability by keeping healthy targets during rollout.

Example (conceptual) inside your ASG resource:

```hcl
resource "aws_autoscaling_group" "web" {
  # ... existing config ...

  health_check_type         = "ELB"
  health_check_grace_period = 90

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 180
    }
    triggers = ["launch_template"]
  }
}

----------------------------------------------------------------------
# This is how look in my lab_55
resource "aws_autoscaling_group" "web" {
  name             = "${var.project_name}-web-asg"
  min_size         = var.web_min_size
  max_size         = var.web_max_size
  desired_capacity = var.web_desired_capacity

  vpc_zone_identifier = local.private_subnet_ids

  health_check_type         = "ELB"
  health_check_grace_period = 90

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }

  target_group_arns = [aws_lb_target_group.web.arn]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = var.asg_min_healthy_percentage
      instance_warmup        = var.asg_instance_warmup_seconds
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Role"
    value               = "web"
    propagate_at_launch = true
  }

  tag {
    key                 = "Version"
    value               = "rolling"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

### Why these values

- `min_healthy_percentage = 50` → for desired=2, replace **one at a time**
- `instance_warmup = 180` → give time for boot + nginx + health checks
- in `terraform/envs/terraform.tfvars` this maps to `asg_min_healthy_percentage` and `asg_instance_warmup_seconds`

> If this is too low, you’ll get churn. If too high, rollout is slow.
> 

**Proof:** refresh started

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
```

Look for:

- `Status`: Pending/InProgress/Successful/Failed/Cancelling/Cancelled
- percentages/progress fields (in JSON)

**Proof:** instances are replaced one by one

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]' \
  --output table
```

**Proof:** sampler BUILD_ID (run curl loop inside proxy SSM session)

```bash
# get this value in local terminal: terraform output -raw alb_dns_name
# then paste it inside SSM session
for i in $(seq 1 20); do
  curl -sS "http://$ALB_DNS/" | egrep -i 'BUILD|Hostname|InstanceId' || true
done
```

You should see the transition: 55-01 -> mixed -> 55-02.

**Failures you must be able to explain**

1. **Refresh keeps running and does not finish**

    Cause: new instances never become healthy (health path, nginx, SG, port, grace/warmup).

2. **ALB starts returning 5xx during refresh**

    Cause: `min_healthy_percentage` is too low or desired capacity is too small.

3. **“I changed AMI but nothing updated”**

    Cause: triggers are not configured, or LT version behavior is not what you assume.
    

## Acceptance

- [ ]  LT takes `image_id` from a variable
- [ ]  ASG health_check_type = ELB
- [ ]  `instance_refresh` is enabled with `launch_template` trigger

---

## C) Runbook — Deploy New AMI (v55-02)

### Step 0 — Freeze the battlefield (recommended)

Avoid surprise scaling while testing rollouts.

- Temporarily set ASG capacity variables in `terraform/envs/terraform.tfvars`:
    - `web_min_size = 2`
    - `web_desired_capacity = 2`
    - `web_max_size = 2`

**WHY** — if ASG scales during instance refresh, you lose observability of rollout behavior:

- was this instance replaced by refresh?
- or added/removed by scaling policy?
- why is target health oscillating?

**Goal:** isolate rollout behavior from scaling behavior.

---

### Step 1 — Bake AMI v55-01

Bake with build marker `55-01`.

**Proof:** record AMI id:

- `ami-AAA...` = `55-01`

---

### Step 2 — Deploy v55-01

Set `web_ami_id = "ami-AAA..."` and apply.

**Proof commands:**

From inside VPC (proxy) via ALB:

```bash
cd lesson51_60/lesson_55/lab_55/terraform/envs
ALB_DNS="$(terraform output -raw alb_dns_name)"
echo "$ALB_DNS"
aws ssm start-session --target "$(terraform output -raw ssm_proxy_instance_id)"
```

Inside SSM session:

```bash
# paste value from local terminal output above
# example: ALB_DNS="internal-lab55-app-alb-xxxx.eu-west-1.elb.amazonaws.com"
for i in $(seq 1 20); do
  curl -sS "http://$ALB_DNS/" | egrep -i 'BUILD|Hostname|InstanceId' || true
done

for i in {1..30}; do
  curl -s -H 'Connection: close' "http://$ALB_DNS/" | grep -E 'BUILD|Hostname|InstanceId' || true
done
```

**Expected:**

- You only see `BUILD_ID: 55-01`

---

### Step 3 — Bake AMI v55-02

Bake with build marker `55-02`.

Record:

- `ami-BBB...` = `55-02`

---

### Step 4 — Deploy v55-02 (trigger refresh)

Update:

- `web_ami_id = "ami-BBB..."`

Then:

```bash
cd lesson51_60/lesson_55/lab_55/terraform/envs
terraform apply
```

This should trigger **instance refresh** automatically (because `launch_template` changed).

---

### Step 5 — Observe refresh (do not guess)

**Get ASG name (once):**

```bash
cd lesson51_60/lesson_55/lab_55/terraform/envs
ASG_NAME="$(terraform output -raw web_asg_name 2>/dev/null || true)"
echo "$ASG_NAME"
```

**Watch refresh:**

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 5 \
  --output table
```

**Watch instance lifecycle:**

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LaunchTemplate.Version,LifecycleState,HealthStatus]' \
  --output table
```

**Watch TG health:**

```bash
TG_ARN="$(terraform output -raw web_tg_arn)"
AWS_PAGER="" aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --output json
```

**Proof via sampling:**

```bash
ALB_DNS="$(terraform output -raw alb_dns_name)"
aws ssm start-session --target "$(terraform output -raw ssm_proxy_instance_id)"
```

Inside SSM session:

```bash
# paste value from local terminal output above
# example: ALB_DNS="internal-lab55-app-alb-xxxx.eu-west-1.elb.amazonaws.com"
for i in $(seq 1 20); do
  curl -sS "http://$ALB_DNS/" | egrep -i 'BUILD|Hostname|InstanceId' || true
done

# or
for i in {1..60}; do
  curl -s -H 'Connection: close' "http://$ALB_DNS/" | grep -E 'BUILD|Hostname|InstanceId' || true
done
```

**Expected outcome:**

- initially mostly `55-01`
- gradually mix
- eventually mostly/all `55-02`

Variables that drive this rollout (1:1 with code in `terraform/envs/terraform.tfvars`):

- `web_ami_id`
- `web_min_size`
- `web_desired_capacity`
- `web_max_size`
- `asg_min_healthy_percentage`
- `asg_instance_warmup_seconds`

## Acceptance

- [ ]  Baseline 55-01 is deployed, sampler shows only 55-01
- [ ]  Applying 55-02 starts refresh automatically
- [ ]  You observe refresh via CLI
- [ ]  Final state: sampler shows only 55-02 and TG healthy

---

## D) Drills (where the lesson lives)

### Drill 1 — Good Rollout (55-01 → 55-02)

**Goal:** verify a healthy rolling update.

**Checklist:**

- [ ]  Refresh starts automatically after `terraform apply`
- [ ]  One instance replaced at a time (for desired=2 and `asg_min_healthy_percentage = 50`)
- [ ]  ALB always has at least 1 healthy target
- [ ]  End state: only `BUILD=55-02`

**Evidence to capture (paste into lesson doc):**

- instance refresh status JSON summary
- target health table at least twice (mid + end)
- curl sampling results (show transition)

---

### Drill 2 — Bad AMI Rollout + Abort

**Make a broken AMI v55-bad:**

- nginx masked, or health check path broken

Example break inside bake:

```bash
systemctl disable --now nginx
systemctl mask nginx
```

Deploy it:

- set `web_ami_id = "ami-BAD..."` → `terraform apply`

**Observe:**

- targets become unhealthy
- `UnHealthyHostCount` rises
- possible 5XX / increased latency
- refresh keeps trying

### Abort the refresh (must do)

```bash
REFRESH_ID="$(aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --query 'InstanceRefreshes[0].InstanceRefreshId' \
  --output text)"

aws autoscaling cancel-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --instance-refresh-id "$REFRESH_ID"
```

**Acceptance:**

- [ ]  You stopped the rollout
- [ ]  You can explain what signals told you to stop (ALB + TG health)
- [ ]  You did not “fix” instances by hand to make bad AMI work

---

### Drill 3 — Rollback (revert AMI + refresh again)

Rollback is not “undo”.

Rollback is “redeploy last known good”.

1. revert `web_ami_id` back to `55-02` or `55-01` AMI
2. `terraform apply`
3. confirm refresh restarts and stabilizes

**Acceptance:**

- [ ]  Targets return healthy
- [ ]  Curl sampling shows only good BUILD id
- [ ]  Refresh completes successfully after rollback

---

### Drill 4 — Warmup & grace tuning

**Goal:** learn why rollouts flap.

Experiment:

- set `asg_instance_warmup_seconds = 30` (too low)
- deploy a “slow boot” variant (e.g., delay service start)
- observe churn

Then fix:

- increase `asg_instance_warmup_seconds` to 180 or higher
- optionally increase `health_check_grace_period`

**Acceptance:**

- [ ]  You caused flapping intentionally
- [ ]  You stabilized rollout by tuning (not by manual patching)

---

## Proof Pack (must-have commands)

### ALB response identity sampler

```bash
cd lesson51_60/lesson_55/lab_55/terraform/envs
ALB_DNS="$(terraform output -raw alb_dns_name)"
echo "$ALB_DNS"
aws ssm start-session --target "$(terraform output -raw ssm_proxy_instance_id)"
```

Inside SSM session:

```bash
# paste value from local terminal output above
# example: ALB_DNS="internal-lab55-app-alb-xxxx.eu-west-1.elb.amazonaws.com"
for i in {1..50}; do
  curl -s -H 'Connection: close' "http://$ALB_DNS/" | grep -E 'BUILD|Hostname|InstanceId' || true
done
```

### Target health

```bash
cd lesson51_60/lesson_55/lab_55/terraform/envs
TG_ARN="$(terraform output -raw web_tg_arn)"
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --output table
```

### Instance refresh status

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 5
```

### CloudWatch sanity

Check:

- `UnHealthyHostCount`
- `HTTPCode_Target_5XX_Count` or `HTTPCode_ELB_5XX_Count`
- `GroupDesiredCapacity` vs `GroupInServiceInstances`

---

## Pitfalls

- No version marker → “did it deploy?” confusion
- Warmup too low → flapping & churn
- Health check path mismatch → endless unhealthy
- Trying to “save” a broken AMI by manual fixes
- Not having a rollback procedure before rollout

---

## Security Checklist

- IMDSv2 required (LT metadata_options)
- No SSH access introduced
- No secrets baked into AMI
- User-data remains minimal
- Rollback is artifact-based (AMI), not instance-based

---

## Summary

lesson_55 turns Instance Refresh into a deployment engine:

- Deploy = update AMI → trigger refresh → observe gates
- Failure = abort refresh → rollback AMI → refresh again
- Proof = ALB truth + TG health + refresh status
