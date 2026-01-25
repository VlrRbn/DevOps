# lesson_50

---

# Launch Template + Auto Scaling Group

**Date:** 2025-01-25

**Topic:** Replace static EC2 instances with an immutable, self-healing web tier using **Launch Template + Auto Scaling Group**, integrated with **ALB** and a **baked AMI**.

---

## Why This Matters

Before lesson_50 I had:

- 2 EC2 instances
- manually attached to ALB
- manually replaced
- manually “fixed”

After lesson_50:

- zero instance identity
- AMI is the artifact
- ASG owns lifecycle
- failures are expected, not scary

**If operate ASG correctly = operate real production systems.**

From this lesson forward:

> Instances are disposable. Architecture is permanent.
> 

---

## Core Mental Model (Read This First)

- **Terraform** defines *what exists*
- **AMI** defines *what an instance is*
- **Launch Template** is the immutable contract
- **ASG** decides *how many live*
- **ALB** decides *who is healthy*

**Terraform never manages EC2 instances directly again.**

This is a hard rule.

---

## Architecture (Target State)

```
Packer
 └── AMI (baked)
        └── Launch Template
              └── Auto Scaling Group (min=2 desired=2 max=3)
                    └── ALB Target Group

```

ASG spans **multiple AZs** using private subnets.

---

## Preconditions

- lesson_49 baked AMI exists and is validated
- Internal ALB + target group already working
- Target group health checks are correct
- Web EC2 instances are **not** managed individually anymore

---

## Goals / Acceptance Criteria

- Launch Template uses **baked AMI**
- ASG spans **2 AZs**
- Desired = 2, Min = 2, Max = 3
- ALB routes traffic via ASG target group
- Manual instance termination → automatic replacement
- No heavy user-data
- No SSH-based recovery

---

The key responsibility chain:

Terraform  →  AMI  →  Launch Template  →  ASG  →  ALB

### a. Terraform — *what exists*

- Defines the **shape of the system**
- Doesn’t know and doesn’t want to know:
    - which EC2 instances are currently alive
    - their uptime
    - what’s in their logs

---

### b. AMI — *what an instance is*

An AMI is an **artifact**, like a Docker image.

It contains:

- Nginx
- the app
- systemd units
- configs
- a health endpoint

Not in the AMI = **doesn’t exist**.

---

### c. Launch Template — *the contract*

The Launch Template tells the ASG:

> “If you need an instance, this is the only allowed way to create it.”
> 

Key points:

- versioned
- immutable
- no logic
- no “what if” branches

---

### d. ASG — *life and death*

The ASG is:

- a counter
- an executioner
- a midwife

It doesn’t **fix** — it **replaces**.

- unhealthy → kill
- below desired → create
- AZ outage → redistribute

---

### e. ALB — *the judge*

The ALB doesn’t care about:

- `systemctl status`
- uptime
- “but it almost works”

It only cares about the **health check**. Period.

- green → receive traffic
- red → 503 / drain

---

“In this setup, EC2 instances are disposable.

If something breaks, I don’t fix instances — I bake a new AMI and let ASG replace them.”

---

# 1) Launch Template — the Instance Contract

### Why Launch Template exists

Launch Template is:

- immutable
- versioned
- reproducible

An ASG does **not** know how to build instances:

- it **doesn’t know** how to install Nginx
- it **doesn’t know** what your app is
- it **doesn’t know** how to fix anything

An ASG can only:

- take a Launch Template
- create an instance
- terminate an instance

It only knows how to **use a template**.

### Example: `aws_launch_template`

```hcl
resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = var.web_ami_id
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
      Name = "${var.project_name}-web"
      Role = "web"
    })
  }
}
```

### Important Rules

- No SSH keys → if you “need SSH,” your process is broken
- No provisioning logic → provisioning happens at bake time
- No “fix on boot” → boot ≠ deploy
- Only what **every instance must have**
    
    If it’s not in the AMI — it’s not real.
    

The Launch Template is the **point of no return**.

After that:

- you **can’t** fix a single instance
- you **shouldn’t** want to
- you **must** think AMI-first

---

# 2) Auto Scaling Group — Lifecycle Owner

```hcl
resource "aws_autoscaling_group" "web" {
  name             = "${var.project_name}-web-asg"
  min_size         = 2
  max_size         = 3
  desired_capacity = 2

  vpc_zone_identifier = local.private_subnet_ids

  health_check_type         = "ELB"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.web.arn]

  tag {
    key                 = "Role"
    value               = "web"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

You **never use** `aws_lb_target_group_attachment` again.

### Mental Model

- ASG owns = instance count
- ALB owns = health (the lie detector)
- Launch Template = the blueprint
- AMI = reality
- Terraform owns = definitions only

---

## STOP CHECKPOINT

Do not continue until:

- ASG shows **2 InService instances**
- Both are registered in target group
- ALB health checks are **green**

If this isn’t true:

- don’t debug the ASG
- debug the AMI or the health check instead

---

# 3) Terraform Cleanup (CRITICAL)

Delete **all** of the following:

- `aws_instance.web_*`
- `aws_lb_target_group_attachment`

Why this is **fatal**:

- Terraform treats those attachments as “the truth”
- the ASG treats its `desired_capacity` as “the truth”
- they start **fighting**

ASG creates → Terraform removes → ASG creates → Terraform removes → …

## What must REMAIN

Terraform manages:

- VPC
- Subnets
- Security Groups
- ALB
- Target Group
- Launch Template
- ASG

Terraform **does NOT** manage:

- the EC2 lifecycle
- instance count
- instance replacement

---

# 4) Drills

## Drill 1 — Manual Termination

**Goal:** Prove instances are disposable.

### Steps

1. Find the current instance IDs that belong to the ASG.
2. Terminate one manually: `aws ec2 terminate-instances --instance-ids i-xxxxxxxxxxxxxx`
3. Observe the **ASG** and the **ALB**

```hcl
# list all lab-instances
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=lab50" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,Role:Tags[?Key=='Role']|[0].Value,PrivIP:PrivateIpAddress,Subnet:SubnetId}" \
  --output table

# статусы в ASG
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "lab50-web-asg" \
  --query "AutoScalingGroups[0].Instances[].{Id:InstanceId,Health:HealthStatus,Lifecycle:LifecycleState}" \
  --output table
  
# состояние targets
TG_ARN="$(terraform output -raw web_tg_arn)"
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query "TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}" \
  --output table
```

**Expected:**

- ASG launches replacement (new instance)
- Desired capacity stays at 2
- TG временно: 1 healthy → then again 2 is healthy
- ALB stays available
- Terraform does nothing

**Acceptance:**

- Instance replaced automatically
- No manual fixes
- No panic

---

## Drill 2 — Bad AMI Rollout

**Goal:** Learn to recognize broken deployments.

1. Bake a bad AMI (disable nginx)
2. Update `web_ami_id`
3. `terraform apply`
4. Watch how the system fails honestly.

```hcl
# list all lab-instances
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=lab50" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,Role:Tags[?Key=='Role']|[0].Value,PrivIP:PrivateIpAddress,Subnet:SubnetId}" \
  --output table

# статусы в ASG
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "lab50-web-asg" \
  --query "AutoScalingGroups[0].Instances[].{Id:InstanceId,Health:HealthStatus,Lifecycle:LifecycleState}" \
  --output table

# состояние targets
TG_ARN="$(terraform output -raw web_tg_arn)"
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query "TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}" \
  --output table

# с инстанса внутри VPC на ALB DNS
SSM_PROXY_ID="$(terraform output -raw ssm_proxy_instance_id)"
ALB_DNS="$(terraform output -raw alb_dns_name)"
aws ssm start-session \
  --target "$SSM_PROXY_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters host=["$ALB_DNS"],portNumber=["80"],localPortNumber=["8080"]

# from laptop
curl -i http://localhost:8080/

# Expected 503 Service Unavailable
```

**Observe:**

- Instances launch
- Targets go unhealthy
- ALB returns 503

**Fix path:**

1. Bake fixed AMI
2. Update AMI ID
3. `terraform apply`

---

## Drill 3 — Manual Change Is a Lie

Goal: prove to yourself with real evidence that manual changes are temporary.

On one web-instance:

```bash
sudo sed -i 's/Web baked by Packer/THIS IS A LIE/g' /var/www/html/index.html
sudo systemctl reload nginx
sudo grep -n "THIS IS A LIE" /var/www/html/index.html || true

# On ssm_proxy
SSM_PROXY_ID="$(terraform output -raw ssm_proxy_instance_id)"
ALB_DNS="$(terraform output -raw alb_dns_name)"
aws ssm start-session \
  --target "$SSM_PROXY_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$ALB_DNS\"],\"portNumber\":[\"80\"],\"localPortNumber\":[\"8080\"]}"

curl -i http://localhost:8080/
```

- Verify via the ALB (port-forward) that the text changed
- Terminate that instance
- Wait for the replacement
- Verify again via the ALB

**Lesson:**

> If it’s not in the AMI, it’s not real.
> 

---

# 5. Scaling Awareness — what Happens

Step 1 — Increase `desired_capacity = 3`

### 1. The ASG sees: “I want 3, I have 2”

- **launches 1 instance**

### 2.  The new instance:

- is created from the **Launch Template**
- is registered in the **Target Group**
- enters the `initial` state

### 3.  The ALB:

- does **NOT** send traffic immediately
- waits for the target to become `healthy`

### 4.  Once the health check is green:

- traffic starts getting distributed
- you now have 3 replicas

Step 2 — Decrease it back to 2

### 1. The ASG picks ONE instance

- not “the bad one”
- not “the old one”
- just any valid candidate

### 2. The ALB:

- moves the target into `draining`
- stops sending **new** requests
- waits for in-flight requests to finish (grace period)

### 3. After draining:

- the ASG **terminates** it
- capacity is back to 2

---

## Common Pitfalls

- Debugging ASG via SSH
- Keeping EC2 resources alongside ASG
- Mixing ASG with manual target group attachments
- Using user-data to fix AMI mistakes
- Baking secrets into AMI
- Forgetting ALB grace period

---

## Security Checklist

- IMDSv2 required
- No inbound SSH
- No secrets in AMI
- IAM via instance profile only
- ALB is the only entrypoint
- Web instances have no public IPs
- SSM access goes through VPC endpoints or tightly scoped egress
- SGs control traffic, not instances

---

## Summary

This lesson moved the web tier from fixed EC2 instances to a fully managed
**Launch Template + Auto Scaling Group** model backed by a baked AMI.

Terraform defines the system, the AMI defines the instance, and the ASG owns
lifecycle. The ALB is the only judge of health.

The core shift is from instance management to capacity management:

- EC2 instances are disposable
- Launch Templates are immutable contracts
- ASG replaces, never “fixes”
- ALB health checks decide who serves traffic
- recovery means **rebuild and redeploy**, not SSH and patch

Drills confirmed automatic replacement, failure visibility, and the illusion
of manual changes.

The result is a self-healing web tier with predictable rollouts and no reliance
on user-data or manual intervention.