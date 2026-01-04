# lesson_39

---

# Cloud 101: VPC, Subnets, Security Groups & IAM (Terraform-ready)

**Date:** 2026-01-02

**Topic:** Understand core **cloud primitives** (VPC, subnets, routing, security groups, IAM) and map them to things what already know (Linux networking, netns, UFW, k8s). Produce a **small “mini-prod” design** and a **Terraform-ready skeleton**.

> This lesson is mostly design + documentation + IaC skeleton,
> 

---

## Goals

- Understand what a **VPC** is and how it maps to your netns + veth/NAT mental model.
- Get comfortable with **public vs private** subnets, route tables, an Internet Gateway, and a NAT Gateway.
- Understand the idea behind **Security Groups** and compare them to UFW/iptables/NetworkPolicy.
- Learn the basics of **IAM** roles and concepts: user, role, policy, least privilege.
- Design a **mini “small-prod” infrastructure** and sketch a `Terraform` skeleton (no real `apply`).

---

## Pocket Cheat

| Concept | Rough analog in your labs | Why it matters |
| --- | --- | --- |
| VPC | Your `ip netns` + bridge + NAT setup | An isolated virtual network in the cloud |
| Subnet | A separate netns or an IP range | Segmentation by purpose/zone (public/private) |
| Internet Gateway (IGW) | Your host acting as a router in the NAT lab | Gives the VPC internet access |
| NAT Gateway | Your NAT namespace + masquerading | Private → Internet access without inbound connections |
| Security Group (SG) | UFW rules / iptables rules | L4 firewall at the instance/ENI level |
| NACL | A coarse ACL on the subnet | Extra protection, but touched less often |
| IAM Role | ServiceAccount + RBAC in k8s | Permissions for services/VMs without passwords |
| IAM Policy | RBAC rules / ClusterRole | JSON rules that define “who can do what” |

---

## Notes

- Almost every cloud has the same set of building blocks — only the names differ.
- Experience with **iptables/NAT/netns/NetworkPolicy/RBAC** already covers half of “cloud networking/security.”
- Terraform here is just an **infrastructure description language**: even without an actual cloud account, can write the configs and run `terraform plan` without applying anything.

---

## Security Checklist

- Don’t put real credentials (e.g., `AWS_ACCESS_KEY_ID`, etc.) into code or the repo.
- Keep all Terraform files free of `backend` config and keys for now. Later, when move to a real cloud, add those properly.
- Anything like `cidr_block = "0.0.0.0/0"` should be treated as intentionally risky and clearly flagged as such.

---

## Pitfalls

- Don’t confuse **Security Groups** with **NetworkPolicy**:
    - SGs control who can connect to a **VM / ENI** over TCP/UDP.
    - NetworkPolicies control who can reach a pod in Kubernetes.
- In the cloud there’s no “localhost”: anything exposed publicly can be reachable from the internet.
- Be careful with resources once start doing real applies.

---

## Layout

```
labs/lesson_39/
├─ cloud-mini-prod-design.md       # prod design (logic + diagram)
└─ terraform/
   ├─ main.tf                      # VPC, subnets, security groups (skeleton)
   ├─ variables.tf                 # inputs: cidr blocks, names, enventory
   └─ outputs.tf                   # IP, IDs, SG IDs

```

---

## 0) Install Terraform

```bash
sudo apt-get update
sudo apt-get install -y gnupg software-properties-common curl

curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
| sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update
sudo apt-get install -y terraform

terraform version

```

## 1) Conceptual map: from labs to cloud

`labs/lesson_39/cloud-mini-prod-design.md` start from:

```markdown
# Cloud 101 — Conceptual Map

## 1. From labs to the cloud

- Linux host with iptables + netns + NAT
  ≈ Cloud VPC + subnets + Internet/NAT gateways

- UFW on Ubuntu
  ≈ Security Group rules for a VM

- Kubernetes NetworkPolicy
  ≈ fine-grained internal traffic control inside a VPC (on top of SG)

- K8s ServiceAccount + Role/RoleBinding
  ≈ IAM roles + policies for cloud services/instances

- VPC is not “one machine” and not “one local network.” It’s a virtual router plus route tables and network interfaces.
  A subnet is not a separate netns — it’s an L3 segment (a CIDR range) within a VPC, tied to an Availability Zone.

+------------------------- Интернет ------------------------------------+
|                              | (публичные IP)                         |
+---------------------------- IGW --------------------------------------+
|            Internet Gateway — “ворота” VPC в интернет                 |
+------------------------------+----------------------------------------+
|                              |                                        |
+---------------------------- VPC --------------------------------------+
|                     Virtual Privat Cloud                              |
|  +---------------------+        +-----------------------+             |
|  |  Public Subnet      |        |  Private App Subnet   |             |
|  |  < Bastion / ALB >  |        |   (web/app/k8s-nodes) |             |
|  |                     |        |                       |             |
|  |  (route:            |        |  (route:              |             |
|  |   0.0.0.0/0 -> IGW) |        |  0.0.0.0/0 -> NAT GW) |             |
|  |         |           |        +-----------------------+             |
|  |         |           |        |                       |             |
|  |  NAT Gateway (EIP)  |        | DB Subnets / isolated |             |
|  |                     |        |    (db, cache)        |             |
|  |                     |        |                       |             |
|  |                     |        | (route: NO 0.0.0.0/0) |             |
|  +---------------------+        +-----------------------+             |
|                                                                       |
+-----------------------------------------------------------------------+

## 2. Traffic flow: “how I SSH in, and why the DB isn’t reachable from the internet”

1) Laptop → Bastion: via the bastion’s public IP (it’s in a public subnet, with a `0.0.0.0/0` route to the IGW, and its SG "inbound tcp/22" allows SSH only from my piblic IP).

2) Bastion → Web: inside the VPC via the web instance’s private IP "example 10.0.2.10", traffic stays within the VPC - using the “local” route for the VPC CIDR (the web SG allows SSH only from the bastion SG).

3) Web → DB: the web instance reaches the DB over the private network; the DB SG allows the DB port "example tcp/5432 or 3306" only from the web SG, the DB is in a private subnet, and it doesn’t need internet access.

4) Internet → DB: not possible, because:
  * the DB has no public IP,
  * the private subnet has no route through the IGW, NO (0.0.0.0/0 → IGW absent)
  * the DB SG has no `0.0.0.0/0` ingress rule, only from SG web.

```

---

## 2) Design a “mini-prod VPC” on paper

Let’s build a typical “small prod” layout:

- 1 VPC: `10.10.0.0/16`.
- 2 public subnets (in different AZs): `10.10.1.0/24`, `10.10.2.0/24`.
- 2 private subnets: `10.10.11.0/24`, `10.10.12.0/24`.
- Internet Gateway.
- NAT Gateway (or conceptually a “NAT instance”) for the private subnets.
- Security Groups:
    - `sg-bastion`: SSH only from my IP.
    - `sg-web`: HTTP/HTTPS from the internet, SSH only from `sg-bastion`.
    - `sg-db`: the DB port only from `sg-web` and/or from the private subnet.

In file `cloud-mini-prod-design.md`:

```markdown
## 3. Mini-prod VPC design

### 3.1 VPC and CIDR

- VPC CIDR: 10.10.0.0/16

### 3.2 Subnets

- Public subnet A: 10.10.1.0/24
- Public subnet B: 10.10.2.0/24
- Private subnet A: 10.10.11.0/24
- Private subnet B: 10.10.12.0/24

### 3.3 Internet access

- Internet Gateway attached to VPC
- Public subnets route 0.0.0.0/0 → IGW
- Private subnets route 0.0.0.0/0 → NAT gateway in public subnet A

### 3.4 Typical instances / roles

- Bastion host in public subnet A:
  - Security group: ssh from my IP only, maybe k8s control-plane access

- Web nodes in public or private subnets:
  - SG: allow 80/443 from internet (public case) or from load balancer
  - SSH only from Bastion SG

- DB in private subnet:
  - SG: allow DB port only from web SG (no direct internet)

```

---

## 3) Terraform skeleton: providers & VPC

Create dir:

```bash
mkdir -p labs/lesson_39/terraform
cd labs/lesson_39/terraform

```

### 3.1 `main.tf` — only skeleton (without real credentials)

Example (AWS-flavored, but no apply):

```hcl
terraform {
  required_version = "~> 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-vpc"
  })

}
```

AWS AZs are named like `eu-west-1a`, but: the letter suffixes aren’t guaranteed to match between accounts,

Better to fetch AZs via `data "aws_availability_zones"`.

### 3.2 variables.tf

```hcl
variable "aws_region" {
  type        = string
  description = "AWS region, e.g. eu-west-1"
  default     = "eu-west-1"
}

variable "project_name" {
  type        = string
  description = "Project prefix for resource names"
  default     = "lab39"
}

variable "environment" {
  type        = string
  description = "Environment dev/test/prod"
  default     = "dev"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Two public subnet CIDR blocks"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Two private subnet CIDR blocks"
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "My public IP/CIDR for SSH to bastion (e.g. 203.0.113.10/32)"
  default     = "0.0.0.0/32"  # WARNING
}
```

### 3.3 outputs.tf

```hcl
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = [for k in sort(keys(aws_subnet.public_subnet)) : aws_subnet.public_subnet[k].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = [for k in sort(keys(aws_subnet.private_subnet)) : aws_subnet.private_subnet[k].id]
}

output "public_subnet_ids_map" {
  description = "Public subnet IDs map"
  value       = { for k, s in aws_subnet.public_subnet : k => s.id }
}

output "security_groups" {
  description = "Security Group IDs"
  value = {
    bastion_sg = aws_security_group.bastion.id
    web_sg     = aws_security_group.web.id
    db_sg      = aws_security_group.db.id
  }
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs"
  value       = { for k, ngw in aws_nat_gateway.nat_gw : k => ngw.id }
}

output "azs" {
  description = "Availability Zones"
  value       = local.azs
}

```

> Even without a real `apply`, run `terraform init` and `terraform validate` locally just to make sure the configuration is valid.
> 

---

## 4) Terraform skeleton: subnets & Internet Gateway

Add in `main.tf` after VPC:

```hcl
# --- Internet Gateway (internet for public) ---

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-igw"
  })

}

# --- Public subnets (2 AZ) ---

resource "aws_subnet" "public_subnet" {

  for_each = {
    a = { cidr = var.public_subnet_cidrs[0], az = local.azs[0] }
    b = { cidr = var.public_subnet_cidrs[1], az = local.azs[1] }
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-public_subnet-${each.key}"
    Tier = "public"
  })
}

# --- Private subnets (2 AZ) ---

resource "aws_subnet" "private_subnet" {

  for_each = {
    a = { cidr = var.private_subnet_cidrs[0], az = local.azs[0] }
    b = { cidr = var.private_subnet_cidrs[1], az = local.azs[1] }
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${var.project_name}-private_subnet-${each.key}"
    Tier = "private"
  })
}
```

and route table:

```hcl
# --- Public Route Table: 0.0.0.0/0 -> IGW ---

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-public_rt"
  })
}

resource "aws_route_table_association" "public_subnet_assoc" {
  for_each = aws_subnet.public_subnet

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rt.id
}
```

and with NAT table:

```hcl
# --- Private Route Tables: 0.0.0.0/0 -> NAT ---

resource "aws_route_table" "private_rt" {
  vpc_id   = aws_vpc.main.id
  for_each = aws_subnet.private_subnet

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw[each.key].id
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-private_rt-${each.key}"
  })
}

resource "aws_route_table_association" "private_rt_assoc" {
  for_each = aws_subnet.private_subnet

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rt[each.key].id
}

# --- NAT Gateway and EIP for Public Subnets ---

# 1) EIP for NAT Gateway Public Subnet
resource "aws_eip" "nat" {
  for_each = aws_subnet.public_subnet
  domain   = "vpc"

  tags = merge(local.tags, {
    Name = "${var.project_name}-nat_eip-${each.key}"
  })
}

# 2) NAT Gateway in Public Subnet
resource "aws_nat_gateway" "nat_gw" {
  for_each = aws_subnet.public_subnet

  subnet_id     = each.value.id
  allocation_id = aws_eip.nat[each.key].id

  tags = merge(local.tags, {
    Name = "${var.project_name}-nat_gw-${each.key}"
  })

  depends_on = [
    aws_internet_gateway.igw,
    aws_route_table_association.public_subnet_assoc
  ]
}
```

---

## 5) Terraform skeleton: Security Groups

Add in `main.tf`:

```hcl
# ***** Security Groups (stateful L4) *****

# --- Bastion: SSH from my IP only ---

resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion_sg"
  description = "SSH from my IP only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from allowed IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-bastion_sg"
  })
}

# --- Web: allow 80/443 from anywhere (lab), SSH only from the bastion SG ---

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web_sg"
  description = "Allow HTTP/S from anywhere, SSH from Bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP 80 from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS 443 from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-web_sg"
  })
}

# --- DB: allow only from Web SG ---

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db_sg"
  description = "Allow DB from Web SG only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from Web SG"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, {
    Name = "${var.project_name}-db_sg"
  })
}

```

This is already a Terraform skeleton that describes the network structure and access rules, even if not applying it yet.

---

Security Groups vs UFW vs NetworkPolicy — don’t mix them up

| Thing | Where it applies | What it controls | Key nuance |
| --- | --- | --- | --- |
| UFW / iptables | inside the VM | packets on the VM’s interfaces | you control the OS |
| Security Group | on the VM’s network interface (in the cloud) | L4 access to the instance | stateful, enforced before the OS |
| NACL | at the subnet level | coarse allow/deny rules | stateless, you must allow both directions |
| NetworkPolicy | inside Kubernetes | pod-to-pod traffic | depends on the CNI; not about public internet access into the VPC |

---

## 6) IAM: short conceptual block

In `cloud-mini-prod-design.md` add:

```markdown
## 4. IAM basics (cloud)

Entities:
- IAM User: a human with long-term credentials (long-lived access keys are evil)
- IAM Role: an identity for services (VMs, k8s nodes, Lambda, CI) without passwords
- Policy: JSON riles: with "Effect / Action / Resource"

Patterns:
- Human → logs into console or uses CLI via IAM user or SSO
- VM or k8s node → gets IAM Role attached (no hardcoded keys)
- CI pipeline → uses IAM Role to push images, apply Terraform, etc.

Mapping to k8s:
- IAM Role ≈ ServiceAccount
- IAM Policy ≈ Role/ClusterRole
- Role attachment to EC2/Node ≈ ServiceAccount + RoleBinding, at the VM/cloud API level

“Least privilege” here is very concrete:
- CI roles should have only what they need, e.g., `ecr:PutImage`, `s3:GetObject` etc., not `AdministratorAccess` 
- That’s like giving your entire pipeline the `cluster-admin` ClusterRole…

```

Keep the mental picture: who gets which permissions, and where keys are stored.

---

## 7) terraform validate / plan (no apply!)

To validate the syntax (without using a real cloud account):

```bash
cd labs/lesson_39/terraform
terraform init
terraform validate

# terraform fmt

```

---

## Core

- [ ]  `cloud-mini-prod-design.md` is written, describing the VPC, subnets, IGW, NAT, SG, and IAM roles at the logical/CIDR level.
- [ ]  `terraform/main.tf` defines the VPC + at least 1 public subnet + an IGW + a route table.
- [ ]  `terraform/main.tf` defines 2–3 Security Groups (bastion/web/db) with clear rules.
- [ ]  `terraform validate` passes without errors.
- [ ]  Both subnet pairs (public/private A,B) are designed with separate route tables.
- [ ]  A NAT Gateway resource is added.
- [ ]  `cloud-mini-prod-design.md` includes a small ASCII diagram / network block diagram.
- [ ]  Can explain: “how to SSH from your laptop to the bastion, then to the web node, and why the DB is not reachable from the internet.”

---

## Acceptance Criteria

- [ ]  Have a clear mental model of “VPC + public/private subnets + IGW + NAT + SG”.
- [ ]  Understand how a Security Group differs from a k8s NetworkPolicy and from UFW.
- [ ]  Have a Terraform skeleton that extend later.
- [ ]  Sketch the network as 3–4 boxes (VPC, subnets, IGW, NAT) and explain step by step how traffic flows.

---

## Summary

- The cloud is the same familiar **VPC, NAT, and firewall** concepts already built on Linux — just wrapped as managed services.
- Have a **mini-prod design doc** and a **Terraform skeleton**.

---

## Artifacts

- `labs/lesson_39/terraform/main.tf`
- `labs/lesson_39/terraform/outputs.tf`
- `labs/lesson_39/terraform/variables.tf`
- `labs/lesson_39/cloud-mini-prod-design.md`