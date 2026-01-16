# lesson_45

---

# VPC Interface Endpoints for SSM

**Private EC2 without NAT, SSH, or Internet**

**Date:** 2025-01-13

**Topic:** Enable **AWS SSM Session Manager** for **private EC2** instances **without NAT / Internet egress** using **Interface VPC Endpoints (PrivateLink)**.

- `ssmmessages`
- `ec2messages` (usually needed; region nuances exist) ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-setting-up-messageAPIs.html))

---

## What I ALREADY have

By this point, I already have:

1. Private EC2 **with no public IP**
2. **No SSH / no bastion**
3. Access **only via SSM**
4. EC2 has an instance profile with `AmazonSSMManagedInstanceCore`
5. VPC DNS is enabled (`enable_dns_support / enable_dns_hostnames`)

This lesson is **not about access** — it’s about **removing internet entirely** while keeping SSM working.

---

## Goals (this is an **architectural choice)**

After this lesson:

- The private EC2 has **NO route to the internet**
- The **NAT Gateway is disabled**
- **SSM Session Manager still works**
- All access is via **IAM + PrivateLink**
- You can **consciously choose** between:
    - NAT-based egress
    - Endpoint-only egress

---

## Why this works (short and to the point)

SSM **does not require inbound connections**.

The agent on the EC2 instance **initiates** HTTPS connections (443) to AWS services.  ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html))

If there’s no NAT, we provide a **private path** using **Interface VPC Endpoints (PrivateLink)**.

Session Manager typically needs **three services**: ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html))

| Endpoint | Why it’s needed |
| --- | --- |
| `ssm` | managed instance control |
| `ssmmessages` | interactive sessions |
| `ec2messages` | control channels / metadata |

Without them, the agent simply **can’t establish a session**.

---

## Preconditions

Quick checkbox:

- [ ]  `enable_dns_support = true`
- [ ]  `enable_dns_hostnames = true`
- [ ]  EC2 role with `AmazonSSMManagedInstanceCore`
- [ ]  EC2 egress **443 is allowed**
- [ ]  SSH and bastion are **removed**

---

## What add in this lesson

1. A **Security Group for VPC Endpoints**
2. **3 Interface VPC Endpoints** in private subnets
3. A flag `enable_vpc_endpoints`
4. The ability to **turn off NAT without losing access**

---

# 1) Security Group for SSM Endpoints

This SG is **not for EC2** — it’s for the **ENIs of the VPC Endpoints**.

### Why it’s needed

An Interface Endpoint = ENI + SG.

If the SG doesn’t allow 443, **SSM just “goes silent.”**

### **Create in network module**.

```hcl
resource "aws_security_group" "ssm_endpoint" {
  name        = "${var.project_name}-ssm_endpoint_sg"
  description = "Allow HTTPS from VPC CIDR to SSM Endpoint"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from VPC CIDR"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-ssm_endpoint_sg"
  })
}

```

Don’t forget to add `ssm_endpoint_sg = aws_security_group.ssm_endpoint.id` in `output "security_groups”`

---

# 2) Interface VPC Endpoints (ssm / ssmmessages / ec2messages)

Put endpoints into the **private subnets**

```hcl
locals {
  private_subnet_ids = [
	  for key in sort(keys(aws_subnet.private_subnet)) :
	  aws_subnet.private_subnet[key].id
  ]
}

```

---

### 2.1 SSM endpoint

```hcl
resource "aws_vpc_endpoint" "ssm" {
  count             = var.enable_ssm_vpc_endpoints ? 1 : 0
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type = "Interface"

  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.ssm_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-ssm_endpoint"
  })
}
```

---

### 2.2 SSM Messages

```hcl
resource "aws_vpc_endpoint" "ssmmessages" {
  count             = var.enable_ssm_vpc_endpoints ? 1 : 0
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type = "Interface"

  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.ssm_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-ssmmessages_endpoint"
  })

}
```

---

### 2.3 EC2 Messages

```hcl
resource "aws_vpc_endpoint" "ec2messages" {
  count             = var.enable_ssm_vpc_endpoints ? 1 : 0
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type = "Interface"

  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.ssm_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2messages_endpoint"
  })

}

```

### Why these three?

Because:

- AWS docs and AWS Knowledge Center both point to these endpoints for private instances using Systems Manager. ([repost.aws](https://repost.aws/knowledge-center/ec2-systems-manager-vpc-endpoints))
- AWS re:Post
- real-world practice — all point to the same thing: **Session Manager is unstable or won’t work without them.**

---

### 2.3 3-in-1

```hcl
locals {
	ssm_services = var.enable_ssm_vpc_endpoints ? toset(["ssm", "ssmmessages", "ec2messages"]) : toset([])
}

resource "aws_vpc_endpoint" "ssm" {
  for_each       = local.ssm_services
  vpc_id         = aws_vpc.main.id
  service_name   = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type = "Interface"

  subnet_ids     = local.private_subnet_ids
  security_group_ids = [aws_security_group.ssm_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-ssm_vpc_endpoint-${each.key}"
  })
}

```

and in `variable` add:

```hcl
variable "enable_ssm_vpc_endpoints" {
  type        = bool
  description = "Enable VPC Endpoints for SSM"
  default     = true
}
```

---

# 3) Most common mistake

If `private_dns_enabled = false`

→ the agent tries to reach public endpoints

→ without NAT, everything breaks

- Private instance SG should allow **egress 443**.
- Endpoints SG allows **ingress 443 from VPC CIDR.**

---

# 4) Test — BEFORE and AFTER NAT

## 4.1 NAT enabled

```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[].{Id:InstanceId,Ping:PingStatus,Platform:PlatformName}' \
  --output table

aws ssm start-session --target i-xxxxxxxx

# Should work
```

---

## 4.2 Disable NAT (after successful bootstrap)

Disable NAT **only after**:

- EC2 finished user-data execution
- SSM agent is installed and running
- SSM session works with NAT enabled

NAT is required for initial package installation unless using a custom AMI.

- `enable_nat = false`
- `terraform apply`

---

## 4.3 Retry SSM

```bash
aws ssm start-session --target i-xxxxxxxx

# S**hould still work**
```

---

## 4.4 Verify internet is truly gone

On the instance:

```bash
curl -I https://httpbin.org/get || echo "expected fail without NAT if outbound blocked"
curl -I -m 10 --connect-timeout 5 https://httpbin.org/get || echo "expected fail without NAT if outbound blocked"

# expected: timeout / failure

```

SSM can work even if that fails — that’s the point.

---

## Pitfalls

- **No `private_dns_enabled = true`** → agent tries public endpoints, fails without NAT.
- Endpoint SG missing inbound 443 from your instance subnets → “TargetNotConnected”.
- VPC DNS settings disabled → Private DNS won’t resolve.
- Instance profile missing `AmazonSSMManagedInstanceCore`. ([docs.aws.amazon.com](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-instance-permissions.html))
- Confusion about endpoints: for Session Manager you generally need **ssm + ssmmessages + ec2messages**.

---

## Core

- [ ]  Added 3 interface endpoints + endpoints SG.
- [ ]  Verified SSM session works to a private instance.
- [ ]  `private_dns_enabled = true`
- [ ]  SSM works **without NAT**
- [ ]  No SSH / no bastion
- [ ]  Architecture documented as “SSM-only”
- [ ]  Document “NAT vs Endpoints”.

---

## How to explain this correctly

> “I removed SSH and bastion hosts, using AWS SSM Session Manager instead.
> 
> 
> For private environments without internet egress, I replaced NAT with VPC Interface Endpoints (ssm, ssmmessages, ec2messages), allowing secure IAM-based access without outbound internet.”
>