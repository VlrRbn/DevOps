# lesson_48

---

# ALB + 2 Targets: Health Checks, Security Groups, Real Load Balancing

**Date:** 2026-01-17

**Topic:** Build an **Application Load Balancer** with:

- 2 EC2 targets (two web instances)
- target group + HTTP listener
- health checks
- proper security groups

> ALB requires at least two subnets in different AZs (standard ALB behavior).
> 
> 
> Default ALB health check path for HTTP is `/`. ([docs.aws.amazon.com](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html))
> 

---

## Goals

- Phase 1: build ALB + TG + health checks.
- Phase 2: harden to internal ALB + access via SSM proxy.
- Run **two web EC2 instances**.
- Register instances in a **target group**.
- Verify:
    - Target health is **healthy**
    - Requests are **load balanced** (see if instance identity in response)

---

### Why ALB comes before AMI (key point)

**If you start with an AMI, you:**

- bake Nginx into an image,
- optimize boot time,
- make everything look nice…

…and then:

- the ALB can’t see the targets,
- health checks fail,
- security groups aren’t wired correctly,
- `/` doesn’t respond,

**If you do the ALB first (like now), you validate:**

- networking,
- security groups,
- health checks,
- routing,
- load balancing.

Only when everything is consistently green does an AMI become just a speed-up.

---

## Layout

```bash
labs/lesson_48/terraform/
├─ modules/
│  └─ network/
│     ├─ main.tf
│     ├─ outputs.tf
│     ├─ variables.tf
│     └─ scripts/
│        └─ web-userdata.sh
└─ envs/
   ├─ main.tf
   ├─ outputs.tf
   ├─ terraform.tfvars
   └─ variables.tf
   
```

---

Request flow:

```bash
Internet
  ↓
ALB (public subnets, 2 AZ)          # The ALB is the only entry point.
  ↓
Target Group
  ↓
EC2 web A (private subnet AZ-a)     # The EC2 instances are never exposed publicly.
EC2 web B (private subnet AZ-b)

```

---

### 0) Preconditions

- Already have:
    - VPC + **two public subnets** (different AZs)
    - **two private subnets**
    - Network module outputs like:
        - `module.network.public_subnet_ids`
        - `module.network.private_subnet_ids`
        - `module.network.vpc_id`
- Your web instances run nginx and return a page (from lesson_44 user_data).

---

## 1) Make 2 web instances (if you only have 1)

If you already have `aws_instance.web`, duplicate it as `aws_instance.web_b` and place into the second private subnet.

Example (keep your existing `web` as A, add B):

```hcl
resource "aws_instance" "web_b" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_web
  subnet_id              = aws_subnet.private_subnet[local.private_subnet_keys[1]].id
  vpc_security_group_ids = [aws_security_group.web.id]

  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_instance_profile.name

  user_data                   = file("${path.module}/scripts/web-userdata.sh")
  user_data_replace_on_change = true

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-web-b"
    Role = "web"
  })

}
```

**Important:** Make sure your web page shows **instance identity** so you can see balancing.

In `web-userdata.sh`, write unique content:

```bash
echo "web OK: $(hostname) $(curl -s http://169.254.169.254/latest/meta-data/instance-id || true)" > /var/www/html/index.html

# curl -i http://localhost/
```

*(If use IMDSv2-only, use the token flow; otherwise skip instance-id and keep hostname.)*

---

## 2) Create a Security Group for the ALB

ALB needs inbound HTTP from the internet and outbound to your web targets.

```hcl
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb_sg"
  description = "ALB SG: inbound 80 only from ssm-proxy SG"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-alb_sg"
  })
}
```

---

## 3) Allow web SG inbound **from ALB SG** on port 80

Web instances must accept traffic from the ALB.

If  `web_sg` is inside the network module, add a rule like:

```hcl
resource "aws_security_group_rule" "web_from_alb" {
  type                     = "ingress"
  description              = "HTTP from ALB SG"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web.id
  source_security_group_id = aws_security_group.alb.id

}
```

*(This is cleaner than opening 80 to the world.)*

---

## 4) Create Target Group + Health Check ([terraform.io](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group))

```hcl
resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-web-tg"
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
    Name = "${var.project_name}-web-tg"
  })

}
```

---

## 5) Attach both instances to the target group

```hcl
resource "aws_lb_target_group_attachment" "web_a" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web_a.id
  port             = 80

}

resource "aws_lb_target_group_attachment" "web_b" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web_b.id
  port             = 80

}
```

---

## 6) Create the ALB (internet-facing, 2 public subnets)

ALB requires **two subnets in different AZs**. ([docs.aws.amazon.com](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html))

```hcl
resource "aws_lb" "app" {
  name               = "${var.project_name}-app-alb"
  internal           = true
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb.id]
  subnets         = [for subnet in aws_subnet.private_subnet : subnet.id]

  tags = merge(local.tags, {
    Name = "${var.project_name}-app-alb"
  })

}
```

How to check LoadBalancer

```hcl
aws elbv2 describe-load-balancers --names lab48-app-alb --query 'LoadBalancers[0].DNSName' --output text

# If you dont know name, but know tag
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, 'alb')].[LoadBalancerName,DNSName]" \
  --output table

```

---

## 7) Listener: HTTP 80 → forward to target group

```hcl
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

}
```

Terraform listener resources: ([registry.terraform.io](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener))

---

## 8) Outputs

```hcl
output "alb_dns_name" {
  description = "DNS name of the internal ALB (reach via SSM port forwarding)"
  value       = aws_lb.app.dns_name
}

output "web_tg_arn" {
  description = "ARN of the web target group"
  value       = aws_lb_target_group.web.arn
}
```

---

## 9) Apply + Verify

```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan
terraform apply

```

### Test from laptop (after hardening form ssm_proxy)

```bash
ALB="$(terraform output -raw alb_dns_name)"

for i in {1..20}; do curl -s "http://$ALB/"; done

TG_ARN="$(terraform output -raw web_tg_arn)"

aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --output table
```

Run multiple times and should see backend identity changes.

### Check health (AWS console)

EC2 → Target Groups → Targets → should be **healthy**.

If targets are unhealthy, use AWS ALB health check troubleshooting flow. ([repost.aws](https://repost.aws/knowledge-center/elb-fix-failing-health-checks-alb))

---

## Pitfalls

- **Targets unhealthy**:
    - web not listening on 80 (`sudo ss -tulpn | grep :80`)
    - web SG doesn’t allow inbound from ALB SG (most common)
    - health check path wrong (use `/` first) ([docs.aws.amazon.com](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html))
- **ALB creation fails**: must select 2 subnets in different AZs ([docs.aws.amazon.com](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html))
- **Reach ALB but see same backend every time**:
    - your response content isn’t unique per instance; print hostname/instance-id.

---

## A) Make ALB **internal** (private-only) + access it via SSM port forward

This is best practice for security labs.

- Set `internal = true`
- Put ALB into **private subnets** instead of public
- Use SSM to access a proxy instance and test the internal ALB from inside the VPC.

(Already know SSM port forwarding from lesson_46.)

---

### A1) Positive test: it should work via the proxy (SSM entrypoint)

Find the proxy instance ID (if it’s tagged `Role=ssm-proxy`):

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=ssm-proxy" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" --output text

# or list all lab-instances
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=lab48" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,Role:Tags[?Key=='Role']|[0].Value,PrivIP:PrivateIpAddress,Subnet:SubnetId}" \
  --output table
```

Start an SSM session:

```bash
aws ssm start-session --target <proxy-instance-id>

```

Inside the session:

```bash
ALB="<internal-alb-dns>"

curl -m 3 -i "http://$ALB/" | head

```

Expected: `HTTP/1.1 200 OK`.

This confirms:

- ALB is reachable **from inside VPC**
- ALB SG allows traffic **only from proxy SG**
- Targets are healthy

---

### A2) Negative test: it should NOT work from web-a/web-b

This test applies **only when web instances are SSM-accessible.**

Start an SSM session on `web-a` or `web-b`:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=web" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" --output text

# or list all lab-instances
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=lab48" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,Role:Tags[?Key=='Role']|[0].Value,PrivIP:PrivateIpAddress,Subnet:SubnetId}" \
  --output table
```

SSM on web-a or web-b:

```bash
aws ssm start-session --target <web-instance-id>

```

Inside the session:

```bash
ALB="$(terraform output -raw alb_dns_name)"

curl -m 3 -v "http://$ALB/" 2>&1 | tail -n +1

```

Applies only when `enable_web_ssm=true` (debug mode)

**Expected:**

- `timeout`
- or `failed to connect`

This confirms:

- ALB **does not accept traffic from web instances**
- Only `ssm-proxy` SG is allowed as a source

---

### A3) Current state: web instances are NOT SSM-accessible

> This is the intended final security model.
> 

### What changed compared to A2

- SSM VPC endpoints allow access **only from `ssm-proxy`**
- `web-a` / `web-b`:
    - have **no SSH**
    - have **no SSM**
    - have **no public IP**
- All management access goes through **a single entrypoint (`ssm-proxy`)**

### Toggle: enable_web_ssm (debug vs prod-like)

- enable_web_ssm = true → web instances can reach SSM endpoints → A2 is runnable
- enable_web_ssm = false → only proxy is manageable via SSM → A2 replaced by A3

### Result

Attempting to start an SSM session on web instances fails:

```bash
aws ssm start-session --target <web-instance-id>

```

**Expected:**

```
An error occurred (TargetNotConnected)

```

This confirms:

- Web instances are **not part of the management plane**
- There is **no lateral movement path**
- ALB access is enforced **purely by Security Groups**

---

## Summary

| Mode | Proxy SSM | Web SSM | Purpose |
| --- | --- | --- | --- |
| Debug / learning | YES | YES | Explicit negative test from web |
| Prod-like (current) | YES | NO | Single secure entrypoint |

> The current setup is more secure than the debug mode.
> 

---

## Acceptance Criteria (`Reworked`)

1. **ALB Architecture**
- The ALB is created as **internal** (`internal = true`)
- The ALB is placed **only in private subnets**
- The ALB has **no public DNS/IP**
- The ALB is reachable **only from within the VPC**

```bash
aws elbv2 describe-load-balancers \
  --names lab48-app-alb \
  --query "LoadBalancers[0].Scheme"

```

Expected: `internal`

2. **Network Access Control (Security Groups)**
- The ALB allows HTTP **only from** the `ssm-proxy` SG
- The ALB does **not** accept traffic from `web-a` / `web-b`
- Web instances allow HTTP **only from** the ALB SG
- No `0.0.0.0/0` ingress on the ALB or Web
- SSH (22) is not opened anywhere

```bash
aws ec2 describe-security-groups \
  --group-ids <alb-sg-id> \
  --query 'SecurityGroups[0].IpPermissions'

```

3. **Expected to Work**
- Connecting to `ssm-proxy` via SSM works
- From `ssm-proxy`, an HTTP request to the ALB returns `200`
- The ALB load-balances between `web-a` and `web-b`

```bash
aws ssm start-session --target <ssm-proxy-id>

```

Inside the session:

```bash
ALB="$(terraform output -raw alb_dns_name)"
for i in {1..10}; do curl -s "http://$ALB/"; done

```

Expected: alternating `hostname` / `instance-id`

4. **Expected to Fail**
- From `web-a` and `web-b`, cannot reach the ALB directly
- An HTTP request to the ALB from `web-*` results in a timeout or connection refused
- `web-*` have no SSM access if `enable_web_ssm = false`

```bash
aws ssm start-session --target <web-instance-id>
curl -m 3 "http://$ALB/"

# Expected: TargetNotConnecte
```

5. **SSM Without NAT (Endpoint-based Access)**
- SSM works without a NAT Gateway
- VPC Interface Endpoints are used:
    - `ssm`
    - `ssmmessages`
    - `ec2messages`
- The endpoint SG allows HTTPS **only from** the `ssm-proxy` SG

```bash
aws ssm describe-instance-information
aws ec2 describe-vpc-endpoints

```

6. **Load Balancer Health**
- The target group shows `healthy` for `web-a` and `web-b`
- The health check path is correct (`/` or `/health`)
- If one web instance is stopped, the ALB still serves traffic

```bash
aws elbv2 describe-target-health \
  --target-group-arn <web-tg-arn>

```

7. **Infrastructure Safety**
- SSH (22) is not opened anywhere
- All EC2 instances use IMDSv2 only
- No public IP on web / proxy
- All access paths are documented and reproducible via Terraform