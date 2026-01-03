# lesson_40

---

# Terraform in Practice: Structure, Variables, tfvars & Modules

**Date:** 2025-01-03

**Topic:** Take cloud skeleton from lesson_39 (VPC, subnets, SGs) and turn it into a **clean Terraform project** with proper structure: `variables.tf`, `outputs.tf`, `*.tfvars` for environments, and a **`network` module**. Learn to run `terraform fmt/validate/plan` safely.

---

## Goals

- Organize Terraform config into **root** and **modules/**.
- Use `variables.tf` + `.tfvars` for environments (dev/stage/prod).
- Understand `locals` to avoid duplicating strings.
- Export useful values via `outputs.tf` (VPC ID, subnet IDs, SG IDs).
- Run `terraform fmt` / `terraform validate` / `terraform plan` (no-`apply`).

---

## Pocket Cheat

| Thing | What it does | Why |
| --- | --- | --- |
| `main.tf` | Entry point, uses modules/resources | “Story of this stack” |
| `variables.tf` | Input variables schema | Doc + validation |
| `*.tfvars` | Concrete values for enventory | dev vs prod differences |
| `locals` | Named constants/expressions | Remove copy-paste |
| `modules/<name>` | Reusable building blocks | VPC / SG / cluster modules |
| `terraform fmt` | Auto-format code | Consistent style |
| `terraform validate` | Static checks | Catch typos early |
| `terraform plan` | Dry-run changes | See what will happen |

---

## Notes

- Terraform **doesn’t like** one huge `main.tf` with everything into it.
- A good structure makes diffs easier to read and PRs easier to review.
- Modules aren’t “complexity for complexity’s sake” — they’re a way to:
    - define VPC/SG/cluster once,
    - reuse it across different projects/environments.

---

## Security Checklist

- **Don’t hardcode** credentials (keys, tokens) in `.tf` files or `tfvars`.
- For real accounts, use environments vars / profiles — but for now you can run without any of that (no-apply plan).
- Never use `cidr_block = "0.0.0.0/0"` without an explicit comment saying it’s for a lab/demo setup.

---

## Pitfalls

- `variable` ≠ `local`.
    - `variable` = an input value from outside.
    - `local` = an “internal variable” for readability/DRY.
- An `output` is only exposed from a module if define it explicitly.
- A module ≠ a separate Terraform project with its own state.
    - State lives at the root configuration level, **not** at the module level (by default).

---

## Layout

```
labs/lesson_40/
├─ docker/
│  └─ docker-compose.yaml
└─ terraform/
   ├─ main.tf                # uses module "network"
   ├─ variables.tf           # root-level inputs: region, env, tags
   ├─ outputs.tf             # outputs from root (pass-through from module)
   ├─ terraform.tfstate
   ├─ envs/
   │  └─ dev.tfvars
   └─ modules/
      └─ network/
         ├─ main.tf          # VPC, subnets, SGs (moved from lesson_39)
         ├─ variables.tf     # module inputs
         └─ outputs.tf       # vpc_id, subnet_ids, sg_ids

```

---

## 1) Move lesson_39 network into a module

Source: your `labs/lesson_39/terraform/main.tf` with `aws_vpc`, `aws_subnet`, `aws_security_group`, etc.

Now we split it up.

### 1.1 Create module directory

```bash
mkdir -p labs/lesson_40/terraform/modules/network

```

Copy the core resources from lesson_39 (take the same files and edit them):

- `aws_vpc`
- `aws_internet_gateway`
- `aws_subnet` (public/private)
- `aws_route_table` / `aws_route_table_association`
- `aws_security_group` (bastion/web/db)

In `labs/lesson_40/terraform/modules/network/main.tf`:

```hcl
terraform {
  required_version = "~> 1.14.0"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))

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
  allocation_id = aws_eip.nat[each.key].allocation_id

  tags = merge(local.tags, {
    Name = "${var.project_name}-nat_gw-${each.key}"
  })

  depends_on = [
    aws_internet_gateway.igw,
    aws_route_table_association.public_subnet_assoc
  ]
}

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

### 1.2 Module variables

`labs/lesson_40/terraform/modules/network/variables.tf`:

```hcl
variable "aws_region" {
  type        = string
  description = "AWS region, e.g. eu-west-1"
  default     = "eu-west-1"
}

variable "project_name" {
  type        = string
  description = "Project prefix for resource names"
  default     = "lab40"
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
  default     = "0.0.0.0/32" # WARNING
}

```

### 1.3 Module outputs

`labs/lesson_40/terraform/modules/network/outputs.tf`:

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

---

## 2) Root config using the module

Now create the root-level config that:

- declares the provider,
- calls `module "network"`,
- exports outputs.

### 2.1 Root `main.tf`

`labs/lesson_40/terraform/main.tf`:

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

module "network" {
  source = "./modules/network"

  aws_region           = var.aws_region
  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  allowed_ssh_cidr     = var.allowed_ssh_cidr
}
```

### 2.2 Root `variables.tf`

`labs/lesson_40/terraform/variables.tf`:

```hcl
variable "aws_region" {
  type = string
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "allowed_ssh_cidr" {
  type = string
}

```

### 2.3 Root `outputs.tf`

`labs/lesson_40/terraform/outputs.tf`:

```hcl
output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "public_subnet_ids_map" {
  value = module.network.public_subnet_ids_map
}

output "security_groups" {
  value = module.network.security_groups
}

output "nat_gateway_ids" {
  value = module.network.nat_gateway_ids
}

output "azs" {
  value = module.network.azs
}

```

---

## 3) Environments via tfvars (`envs/dev.tfvars`)

Create dir `envs`:

```bash
mkdir -p labs/lesson_40/terraform/envs

```

Create `labs/lesson_40/terraform/envs/dev.tfvars`:

```hcl
aws_region           = "eu-west-1"
project_name         = "lab40"
environment          = "dev"
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
allowed_ssh_cidr     = "0.0.0.0/0"    # WARNING

```

---

## 4) Terraform workflow: fmt, validate, plan (no apply)

Inside `labs/lesson_40/terraform`:

```bash
terraform init
terraform fmt
terraform validate

# dry-run with dev.tfvars
terraform plan -var-file=envs/dev.tfvars

```

If don’t have a real AWS account/credentials:

- `terraform init` and `terraform validate` should work.
- `terraform plan` may complain about provider auth — might need `refresh=false`, etc.

The point of the lesson is the **structure**, not actually creating resources.

---

## Quick start: Terraform + LocalStack (no AWS account)

Start LocalStack with Docker Compose

Create `docker-compose.yml`:

```yaml
services:
  localstack:
    image: localstack/localstack:latest
    ports:
      - "4566:4566"
    environment:
      - SERVICES=ec2,sts,iam
      - DEBUG=1
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"

```

Install Terraform — and `tflocal` (a wrapper that automatically wires up the endpoints).

Option 1: `pipx`

`pipx` installs the utility into an isolated virtualenv and adds it to your `PATH`.

```bash
sudo apt update
sudo apt install -y pipx

pipx ensurepath

# reload terminal or:
source ~/.profile

pipx install terraform-local
tflocal --version

# NEXT
tflocal init
tflocal plan -var-file=envs/dev.tfvars

```

Option 2: a virtual environment next to the project.

```bash
sudo apt update
sudo apt install -y python3-full python3-venv

python3 -m venv .venv

source .venv/bin/activate

pip install -U pip
pip install terraform-local

# NEXT
tflocal --version
tflocal plan -var-file=envs/dev.tfvars

```

What to do next - try an `apply` in LocalStack.

```bash
tflocal apply -var-file=envs/dev.tfvars

terraform output
terraform state list | wc -l
terraform state list | head

```

---

## 5) Short doc: “How to read my Terraform repo”

Add `labs/lesson_40/README_terraform.md`:

```markdown
# How to read my Terraform layout (lesson_40)

Root:
- main.tf: defines provider and calls module "network"
- variables.tf: defines root-level inputs
- outputs.tf: exposes IDs from modules
- envs/dev.tfvars: concrete values for Dev environment

Module "network":
- modules/network/main.tf: VPC, subnets, IGW, route tables, security groups
- modules/network/variables.tf: configurable inputs (CIDRs, tags, region)
- modules/network/outputs.tf: VPC ID, subnet IDs, SG IDs for root usage

Commands:
- terraform init
- terraform fmt
- terraform validate
- terraform plan -var-file=envs/dev.tfvars

```

---

## Core

- [ ]  Moved the network resources from lesson_39 into the `modules/network` module.
- [ ]  The root `main.tf` now uses `module "network"` instead of raw resources.
- [ ]  `variables.tf` / `outputs.tf` are cleanly defined both at the root level and in the module.
- [ ]  Have `envs/dev.tfvars`, and `terraform fmt` / `terraform validate` pass.
- [ ]  Added another env (e.g., `stage.tfvars`) CIDR.
- [ ]  In `module/network`, Added another subnet pair (public_b/private_b) and their outputs.
- [ ]  Can explain out where to find:
    - input parameters,
    - outputs,
    - and how the module is connected to the root.

---

## Acceptance Criteria

- [ ]  Understand the difference between the root config and a module.
- [ ]  Can look at `main.tf` and understand the high-level story of the infrastructure.
- [ ]  Can add another module (e.g., `modules/bastion`) using the same pattern.
- [ ]  Not afraid of seeing `modules/` and `envs/` in someone repo — you understand how to work with them.

---

## Summary

- Turned “one big `main.tf`” into a **readable Terraform project** with modules and environments.
- Laid the groundwork: next can safely add **remote state**, **CI (terraform plan in PRs)**, and real cloud applies without having to rebuild the structure.

---

## Artifacts

- `labs/lesson_40/docker/docker-compose.yml`
- `labs/lesson_40/terraform/main.tf`
- `labs/lesson_40/terraform/variables.tf`
- `labs/lesson_40/terraform/outputs.tf`
- `labs/lesson_40/terraform/envs/dev.tfvars`
- `labs/lesson_40/terraform/modules/network/main.tf`
- `labs/lesson_40/terraform/modules/network/variables.tf`
- `labs/lesson_40/terraform/modules/network/outputs.tf`
- `labs/lesson_40/terraform/terraform.tfstate`
