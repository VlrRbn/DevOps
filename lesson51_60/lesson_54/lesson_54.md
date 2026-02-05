# lesson_54

---

# Blue/Green Deployments with ALB + ASG

**Date:** 2026-02-03

**Focus:** Deploy new versions safely using **two target groups** and **controlled traffic shifting**, with rollback that’s basically “flip the switch”.

---

## Target Architecture

```
                 ┌──────────────┐
Client ───────►  │     ALB      │
                 │ Listener :80 │
                 └──────┬───────┘
                        │ (weights)
         ┌──────────────┴──────────────┐
         │                               │
   Target Group BLUE                Target Group GREEN
   (ASG blue)                       (ASG green)
   AMI v1                           AMI v2
```

You will be able to do:

- 100/0 (all blue)
- 90/10 (canary-ish)
- 0/100 (full cutover)
- instant rollback (back to blue)

---

## Goals / Acceptance Criteria

- [ ]  Two target groups exist: `blue` and `green`
- [ ]  Two ASGs exist: `web-blue-asg` and `web-green-asg`
- [ ]  ALB listener forwards traffic with **weights**
- [ ]  90/10 shift works and is observable via responses
- [ ]  Rollback works instantly (weights back)
- [ ]  A bad green deploy never takes down prod traffic

---

## Preconditions

- You can reach the internal ALB via proxy (your current model)
- Web page prints instance identity (hostname/instance-id or build stamp)
- ASG + Launch Template already working (lesson_50–51)

---

## A) Prep — make versions visible

Before you touch routing, ensure your web page includes a **version marker**.

The page/response must include a **version marker**, so a single `curl` shows whether the response came from **blue** or **green**.

### Bake it into AMI (lesson_49 pattern)

- BLUE AMI renders “Version: blue”
- GREEN AMI renders “Version: green”

### How to implement the version marker correctly

The marker should be:

- **in the response body** (HTML/JSON — doesn’t matter)
- **not dependent on runtime environment**
- preferably includes a **build stamp** (for example `blue-20260203-01`), so you see the exact build, not just the color

Version via ALB

```bash
# List all instances
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=lab54" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,Role:Tags[?Key=='Role']|[0].Value,PrivIP:PrivateIpAddress,Subnet:SubnetId}" \
  --output table

# Check via ALB
aws ssm start-session --target "$(terraform output -raw ssm_proxy_instance_id)"
export ALB_DNS="internal-lab54-app-alb-127..."
for i in $(seq 1 20); do
  curl -sS "http://$ALB_DNS/" | egrep -i 'version|host' || true
done

# Check via local port
aws ssm start-session \
  --target "$(terraform output -raw ssm_proxy_instance_id)" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$(terraform output -raw alb_dns_name)\"],\"portNumber\":[\"80\"],\"localPortNumber\":[\"8080\"]}"

# In a second terminal on your laptop
for i in $(seq 1 20); do
  curl -sS "http://localhost:8080/" | egrep -i 'version|host' || true
done
```

**Expected:** you always see `version=blue` (until green is attached).

On the instance, verify the service directly via SSM

```bash
sudo systemctl status nginx --no-pager
sudo journalctl -u nginx -n 50 --no-pager

curl -sS -D- http://127.0.0.1/ | head -n 40
```

The ALB can be healthy while the content is wrong (or vice versa). We verify **locally** and **through the balancer**.

Acceptance:

- [ ]  **`curl http://$ALB_DNS/`** **shows** version/build/host
- [ ]  Locally on the instance **`systemctl status nginx`** = active (running)
- [ ]  Health endpoint/path is clear and consistent in meaning for future blue/green

---

## B) Add GREEN Target Group + Weighted Forward Action

### 1) Create second TG

- `aws_lb_target_group.web["blue"]`
- `aws_lb_target_group.web["green"]`

```hcl
# Target group for web instances behind the ALB.
resource "aws_lb_target_group" "web" {
  for_each = local.web_variants

  name     = "${var.project_name}-web-${each.key}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.tags, {
    Name    = "${var.project_name}-web-${each.key}-tg"
    Version = each.value.version
  })

}

# --- Web variants and capacities for blue/green deployment ---
# --- Put it in locals{}
  web_variants = {
    blue = {
      ami_id  = var.web_ami_blue_id
      version = "blue"
    }
    green = {
      ami_id  = var.web_ami_green_id
      version = "green"
    }
  }

  web_capacity = {
    blue = {
      min     = var.blue_min_size
      desired = var.blue_desired_capacity
      max     = var.blue_max_size
    }
    green = {
      min     = var.green_min_size
      desired = var.green_desired_capacity
      max     = var.green_max_size
    }
  }
```

Same health checks, same port, same VPC.

### 2) Listener forwards to both TGs with weights

Terraform pattern (conceptual):

- Listener default action: `forward`
- `forward { target_group { arn = blue; weight=100 } target_group { arn = green; weight=0 } }`

**WHY 0?**

- Weight **0** is your **safety fuse**: green can be running, but no traffic goes there.
- The ALB already “knows” about green — later you only change the numbers, without rewiring.

In `aws_lb_listener` (port 80) set **default_action** to `forward` with a `forward` block.

```hcl
# HTTP listener forwarding to web target group.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.web["blue"].arn
        weight = var.traffic_weight_blue
      }

      target_group {
        arn    = aws_lb_target_group.web["green"].arn
        weight = var.traffic_weight_green
      }
    }
  }

}
```

Does the listener actually have two TGs?

```bash
export ALB_ARN="..."

aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --query 'Listeners[].DefaultActions'
```

You should see `Type=forward` and **two entries** for target groups with weight 100/0.

Green TG exists and is empty (for now)

```bash
aws elbv2 describe-target-groups \
  --query 'TargetGroups[?contains(TargetGroupName, `green`)].{Name:TargetGroupName,Arn:TargetGroupArn,Port:Port,HC:HealthCheckPath}'

export TG_GREEN_ARN="arn:aws:elasticloadbalancing:eu-west-1:179151669003:targetgroup/lab54-web-green-tg/5f3..."

aws elbv2 describe-target-health --target-group-arn "$TG_GREEN_ARN"
```

**Expected:** targets = [none].

Acceptance:

- [ ]  **`web_green`** TG is created and health check settings **match** blue
- [ ]  Listener config shows both TGs attached
- [ ]  Traffic at 100/0 **provably** goes only to blue

---

## C) Add second ASG (GREEN)

Create:

- `aws_launch_template.web_green` (uses **new AMI**)
- `aws_autoscaling_group.web_green` attached to `web_green` TG

**WHY?:** Launch Template = the instance “contract”. ASG = the capacity “orchestrator”. TG = where the ALB sends traffic.

```hcl
# Web instance template for Auto Scaling Group.
resource "aws_launch_template" "web" {
  for_each = local.web_variants

  name_prefix   = "${var.project_name}-web-${each.key}-"
  image_id      = each.value.ami_id
  instance_type = var.instance_type_web

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
      Name    = "${var.project_name}-web-${each.key}"
      Role    = "web"
      Version = each.value.version
    })
  }
}

# Auto Scaling Group for web instances.
resource "aws_autoscaling_group" "web" {
  for_each = local.web_variants

  name             = "${var.project_name}-web-${each.key}-asg"
  min_size         = local.web_capacity[each.key].min
  max_size         = local.web_capacity[each.key].max
  desired_capacity = local.web_capacity[each.key].desired

  vpc_zone_identifier = local.private_subnet_ids

  health_check_type         = "ELB"
  health_check_grace_period = 90

  launch_template {
    id      = aws_launch_template.web[each.key].id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.web[each.key].arn]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 180
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
    value               = each.value.version
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

**Pitfalls:**

Wrong SG.

- The instance SG must be the same **web SG** that **only allows from the ALB SG**.

`health_check_type` is not ELB.

- If you leave EC2, the ASG may consider the instance “ok” while it is “unhealthy” in the TG.

Grace period too small.

- If nginx doesn’t start quickly, the ALB will fail a few checks and the ASG will start **replacing** instances in a loop.

Did the green ASG actually launch instances?

```bash
export ASG_GREEN_NAME="lab54-web-green-asg"
export ASG_BLUE_NAME="lab54-web-blue-asg"

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_GREEN_NAME" \
  --query 'AutoScalingGroups[0].Instances[].InstanceId' --output text
```

Check activity (the “black box” of what ASG did):

```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "$ASG_GREEN_NAME" \
  --query 'Activities[].{Status:StatusCode,Desc:Description,Cause:Cause,Start:StartTime,End:EndTime}'
```

Are green targets healthy?

```bash
export TG_GREEN_ARN="arn:aws:elasticloadbalancing:eu-west-1:179151669003:targetgroup/lab54-web-green-tg/ddc..."

aws elbv2 describe-target-health \
  --target-group-arn "$TG_GREEN_ARN" \
  --query 'TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason,Desc:TargetHealth.Description}'
```

On the green instance, nginx is alive and returns the correct version

```bash
# Via SSM on a green instance:
sudo systemctl status nginx --no-pager
sudo journalctl -u nginx -n 80 --no-pager
curl -sS http://127.0.0.1/ | egrep -i 'version|host'
```

Mini-drill: “bad green without user impact”

```bash
sudo systemctl stop nginx
```

Check:

- green TG becomes unhealthy (see `describe-target-health`)
- `curl http://$ALB_DNS/` still shows **only blue** (because green weight is 0)

Acceptance:

- [ ]  **`web_green`** LT uses the **GREEN AMI** and IMDSv2 required
- [ ]  **`web_green`** TG shows **healthy targets**
- [ ]  BLUE traffic has not changed (weights still 100/0)

---

## D) Traffic Shifting Drills

### Drill 1 — 100/0 baseline

- weights: blue 100, green 0
- curl 30 times → only blue

---

### Drill 2 — 90/10

- weights: blue 90, green 10
- curl 50–100 times → see some green

Make sure **green targets are healthy**

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_GREEN_ARN" \
  --query 'TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason,Desc:TargetHealth.Description}' \
  --output table
```

In the listener forward:

- traffic_weight_blue = 90
- traffic_weight_green = 10

Did the weights actually apply?

```bash
aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
  --query 'Listeners[].DefaultActions' --output json
```

**Proof:** traffic is actually distributed (counter)

```bash
for i in $(seq 1 200); do
  curl --no-keepalive -s "http://$ALB_DNS/" \
    | egrep -i 'version=|Version:' | head -n 1
done | awk '
  /blue/  {b++}
  /green/ {g++}
  END {printf("blue=%d green=%d total=%d green_pct=%.1f%%\n", b, g, b+g, (g*100)/(b+g))}
'
```

**Expected:** around 10% (blue=186 green=14 total=200 green_pct=7.0%).

**Proof:** no errors (HTTP codes)

```bash
for i in $(seq 1 200); do
  curl --no-keepalive -s -o /dev/null -w "%{http_code}\n" "http://$ALB_DNS/"
done | sort | uniq -c
```

**Expected:** all `200`.

---

### If green does not appear at 90/10 (and how to fix it)

1. **Green targets unhealthy / flapping**
    
    **Proof:** `describe-target-health` shows `unhealthy`.
    
    Fix: resolve nginx/health path/SG/port mismatch.
    
2. **Stickiness enabled**
    
    If enabled, a single client can stick to blue.
    
    Fix: disable stickiness, or test in parallel from multiple clients.
    
3. **Too little green capacity**
    
    If green desired=1 and it is under load/restarting, the ALB will avoid it.
    
    Fix: temporarily set `desired_capacity=2` for green.
    
4. **You are hitting a different listener rule**
    
    **Proof:** listener rules exist on path/host.
    
    Fix: check `describe-rules` and confirm requests hit the default action.
    

---

### Drill 3 — 0/100 cutover

- blue 0, green 100
- verify all green

Check how many instances are in the green ASG:

```bash
export PROJECT="lab54"

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "${PROJECT}-web-green-asg" \
  --query 'AutoScalingGroups[0].DesiredCapacity' --output text
```

**Proof:** both green targets are healthy

```bash
export TG_GREEN_ARN="arn:aws:elasticloadbalancing:eu-west-1:179151669003:targetgroup/lab54-web-green-tg/ddc..."

aws elbv2 describe-target-health --target-group-arn "$TG_GREEN_ARN" \
  --query 'TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
  --output table
```

**Proof:** weights actually became 0/100

```bash
export ALB_ARN="arn:aws:elasticloadbalancing:eu-west-1:179151669003:loadbalancer/app/lab54-app-alb/97f..."

aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
  --query 'Listeners[].DefaultActions' --output json
```

**Proof:** responses are only green

```bash
export ALB_ARN="arn:aws:elasticloadbalancing:eu-west-1:179151669003:loadbalancer/app/lab54-app-alb/97f..."

for i in $(seq 1 120); do
  curl --no-keepalive -s "http://$ALB_DNS/" | egrep -i 'version=|Version:' | head -n 1
done | awk '
  /blue/  {b++}
  /green/ {g++}
  END {printf("blue=%d green=%d total=%d\n", b, g, b+g)}
'
```

**Expected:** `blue=0`.

---

### Drill 4 — Instant Rollback (blue 100, green 0)

Rollback is complete when all of the following are true:

- traffic_weight_blue = **100**
- `curl` 120+ times → **only blue**
- HTTP codes (almost all 200)

Acceptance:

- [ ]  You can move traffic gradually
- [ ]  You can rollback in < 1 minute

---

## E) Failure Drills (the real learning)

### Drill 5 — Bad GREEN AMI (broken release)

**Goal**

- green instances launch, but are **unhealthy** in the TG
- user traffic is not impacted (because weight is 0 or 10)
- recovery = **new AMI** → update LT → ASG replaces instances

**Steps**

- In the AMI bake (packer), make `/` return 404 (or nginx not start) while the TG checks `/`.
- Replace the bad AMI in `web_ami_green_id`
- green TG goes unhealthy, blue is alive (`aws elbv2 describe-target-health`)
- Keep weights at 0 or 10
- Confirm user impact is limited or none
- Rollback / fix by new AMI

**Important: ASG vs ALB**

- ALB only **marks** the target as Unhealthy and stops routing traffic.
- ASG with `health_check_type = "ELB"` **replaces** those instances.
- If the AMI is “bad,” replacements will loop **indefinitely** (expected).

Acceptance:

- [ ]  Green fails without taking prod down
- [ ]  You recovered by rebuild + redeploy

---

### Drill 6 — Slow Start + cutover stability

- Set TG slow start and raise healthy threshold.
- Cut over gradually and compare latency / 5xx.

In `network/main.tf`:

```hcl
# Target group for web instances behind the ALB.
resource "aws_lb_target_group" "web" {
  slow_start = var.tg_slow_start_seconds

  health_check {
    healthy_threshold = var.health_check_healthy_threshold
  }
}
```

In `network/variables.tf`:

```hcl
variable "tg_slow_start_seconds" {
  type        = number
  description = "Target group slow start duration in seconds (30-900)"
  default     = 60

  validation {
    condition     = var.tg_slow_start_seconds >= 30 && var.tg_slow_start_seconds <= 900
    error_message = "tg_slow_start_seconds must be between 30 and 900."
  }
}

variable "health_check_healthy_threshold" {
  type        = number
  description = "Number of consecutive successful checks before considering target healthy"
  default     = 2
}
```

Cutover stability = wait for green targets to be healthy before shifting weights:

```bash
aws elbv2 wait target-in-service --target-group-arn "$TG_GREEN_ARN"
```

Acceptance:

- [ ]  Bad green release makes the TG **unhealthy**
- [ ]  With weight 0 (or 10) users are barely impacted
- [ ]  Recovery is done via a **new AMI**, not a manual fix
- [ ]  You can explain why this is the correct approach

---

## Pitfalls

- Forgetting to keep health check settings consistent across TGs
- Cutting over before green is healthy
- Weight changes without verifying responses
- Not keeping blue intact until after full validation
- Shifting weights while `green_desired_capacity = 0` (will cause 5xx for the green share)
- Health check path mismatch (TG checks `/` but you break `/health`)
- Stickiness can hide green at 90/10 for a single client
- Bad AMI + `health_check_type = "ELB"` causes an ASG replacement loop

---

## Security Checklist

- No SSH
- No public ALB exposure introduced
- Web SG still only allows from ALB SG
- IMDSv2 remains required
- Rollback path exists before rollout
- ALB is internal and reachable only from the SSM proxy SG
- Web instances have no public IPs
- Instance role is least-privilege (SSM managed instance policy)
- SSM endpoints are restricted to the proxy SG

---

## Summary

- Working blue/green setup: two TGs/ASGs behind an internal ALB, clear version markers, and safe traffic shifting with instant rollback.
- Observed how bad green behaves under ELB health checks, and added slow start + “wait for healthy” before cutover.
- Bottom line: predictable releases with real checks at every step.