# lesson_42

---

# Terraform Safe Ops: cheap vs full envs, state hygiene, apply/destroy runbook

**Date:** 2025-01-06

**Topic:** Make Terraform workflow **safe, repeatable, and cost-controlled**:

- add two environments: **cheap** (minimal spend) and **full** (real multi-AZ + NAT design)
- build a clean **apply/destroy runbook**
- learn **state hygiene** basics and how to avoid “I recreated everything”
- add a “destroy guard” checklist to prevent surprises

> Goal: Practice in AWS without anxiety and without mystery bills.
> 

---

## Goals

- Create **two tfvars** profiles:
    - `cheap.tfvars`: minimal resources to learn basics with low cost
    - `full.tfvars`: multi-AZ with NAT (architecture practice), used only for short sessions
- Standardize commands for:
    - init / validate / plan / apply / destroy
- Learn the “3 golden rules” of Terraform state:
    - never manually edit state
    - prefer refactor tools (`moved` blocks or `state mv`) instead of recreating
    - always know what workspace/env you’re running

## Non-goals

- Terraform workspaces (intentionally not used)

---

## Pocket Cheat

| Task | Command | Why |
| --- | --- | --- |
| Format | `terraform fmt -recursive` | Clean diffs |
| Validate | `terraform validate` | Catch errors early |
| Plan (env) | `terraform plan -var-file=envs/cheap.tfvars` | Preview changes |
| Apply (env) | `terraform apply -var-file=envs/cheap.tfvars` | Create |
| Destroy (env) | `terraform destroy -var-file=envs/cheap.tfvars` | Remove everything |
| List state | `terraform state list` | See what TF owns |
| Show resource | `terraform state show <addr>` | Debug exactly what exists |
| Remove from state | `terraform state rm <addr>` | “Stop managing this” (careful - it’s last chance) |
| State move | `terraform state mv a b` | Refactor without recreate |

---

## Layout

Inside Terraform root (lesson_40 structure or copy to lesson_42):

```
labs/lesson_42/terraform/
├─ modules/
│  └─ network/                 # (VPC/Subnets/RT/NAT/SG/EC2)
│     ├─ main.tf
│     ├─ variables.tf
│     ├─ outputs.tf
│     └─ scripts/
│        └─ web-userdata.sh
├─ env-cheap/
│  ├─ main.tf
│  ├─ providers.tf
│  ├─ versions.tf
│  └─ terraform.tfvars
└─ env-full/
│  ├─ main.tf
│  ├─ providers.tf
│  ├─ versions.tf
│  └─ terraform.tfvars
├─ README.md
└─ RUNBOOK.md

```

---

## 1) Why “cheap vs full”

**Full** network design is correct for reliability (multi-AZ, NAT per AZ), but:

- NAT Gateways cost money while running
- Easy to forget them

So:

- **cheap** = for 80% of learning (VPC + 1 public subnet + SG + maybe 1 instance)
- **full** = for short bursts (NAT, private routing, multi-AZ)

---

## 2) Create env-cheap/terraform.tfvars (low spend)

Create `labs/lesson_42/terraform/env-cheap/terraform.tfvars`:

```hcl
aws_region   = "eu-west-1"
project_name = "lab42"
environment  = "cheap"

# Keep it simple: still use /16 for VPC, but only use 1 subnet per tier
vpc_cidr = "10.40.0.0/16"

# Only 1 public + 1 private subnet for cheap setup
public_subnet_cidrs  = ["10.42.1.0/24"]
private_subnet_cidrs = ["10.43.11.0/24"]

# IMPORTANT: set to real public IP /32 before apply
allowed_ssh_cidr = "0.0.0.0/0" # WARNING need PUBLIC_IP/32

# No NAT at all is the cheapest
# enable_nat          = false
# enable_full_ha      = false
enable_nat = true

key_name              = "lab40_terraform"
instance_type_bastion = "t3.micro"
instance_type_web     = "t3.micro"
public_key            = "*********"

```

### How becomes truly cheap

Need one extra code in Terraform:

- **feature flag** to disable NAT + second AZ resources.

Add to `variables.tf`:

```hcl
variable "enable_full_ha" {
  type        = bool
  description = "Enable full HA setup. When true: multi-AZ + NAT gateways. When false: minimal/cheap mode."
  default     = false
}
```

Then implement conditional creation:

- if `enable_full_ha = false`:
    - create only `public_subnet["a"]` and `private_subnet["a"]`
    - create only one NAT

**No NAT at all** is the cheapest. Private instances won’t have outbound internet—fine for many labs.

Cheap mode can still teach:

- VPC + IGW + SG + bastion/web in public subnet
- routing basics
- IAM + tags + outputs

But it won't work with:

- `apt update` / `snap install` / `curl google.com` on web in private subnet

---

## 3) Create env-full/terraform.tfvars (real setup)

`labs/lesson_42/terraform/env-full/terraform.tfvars`:

```hcl
aws_region            = "eu-west-1"
project_name          = "lab42"
environment           = "full"

vpc_cidr              = "10.30.0.0/16"

public_subnet_cidrs   = ["10.32.1.0/24", "10.32.2.0/24"]
private_subnet_cidrs  = ["10.33.11.0/24", "10.33.12.0/24"]

allowed_ssh_cidr      = "0.0.0.0/0" # WARNING need PUBLIC_IP/32

enable_full_ha        = true
enable_nat            = true

key_name              = "lab40_terraform"
instance_type_bastion = "t3.micro"
instance_type_web     = "t3.micro"
public_key            = "*********"

```

---

Add to `variables.tf`:

Enable NAT Gateway for private subnets to allow outbound Internet access. When false, private subnets have no Internet egress.

```hcl
variable "enable_nat" {
  type        = bool
  description = "If true: private subnets get outbound internet via NAT. If false: private has no internet."
  default     = false
}
```

---

Change `main.tf`:

```hcl
# Added subnet map generation in `locals` based on the actual lists
locals {
  az_letters = ["a", "b", "c", "d", "e", "f"]
  azs        = slice(data.aws_availability_zones.available.names, 0, max(length(var.public_subnet_cidrs), length(var.private_subnet_cidrs)))

  public_subnet_map = {
    for idx, cidr in var.public_subnet_cidrs :
    local.az_letters[idx] => { cidr = cidr, az = local.azs[idx] }
  }

  private_subnet_map = {
    for idx, cidr in var.private_subnet_cidrs :
    local.az_letters[idx] => { cidr = cidr, az = local.azs[idx] }
  }

  public_subnet_keys = sort(keys(local.public_subnet_map))
  
  # fixed the NAT logic *single NAT vs per-AZ*
  nat_keys = var.enable_nat ? (
    var.enable_full_ha ? local.public_subnet_keys :
    (length(local.public_subnet_keys) > 0 ? [local.public_subnet_keys[0]] : [])
  ) : []

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# --- Private Route Tables: 0.0.0.0/0 -> NAT ---

resource "aws_route_table" "private_rt" {
  for_each = local.private_subnet_map
  vpc_id   = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.enable_full_ha ? aws_nat_gateway.nat_gw[each.key].id : aws_nat_gateway.nat_gw[local.public_subnet_keys[0]].id
    }
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-private_rt-${each.key}"
  })
}
```

“NAT per AZ”.

1. If `enable_full_ha = true`:
- For private route table `"0"`, use NAT `"0"`.
- For private route table `"1"`, use NAT `"1"`.
1. If `enable_full_ha = false`:

All private route tables point to a single NAT in the “first” public subnet: `local.public_subnet_keys[0]`

This is the “cheaper” mode: 1 NAT instead of 2.

---

NAT Gateways are created in selected **public subnets**: either **one per AZ** (HA) or **a single shared NAT** in the first public subnet (cheap mode).

```hcl
# 1) EIP for NAT Gateway Public Subnet
resource "aws_eip" "nat" {
  for_each = toset(local.nat_keys)
  domain   = "vpc"

  tags = merge(local.tags, {
    Name = "${var.project_name}-nat_eip-${each.key}"
  })
}

# 2) NAT Gateway in Public Subnet
resource "aws_nat_gateway" "nat_gw" {
  for_each = toset(local.nat_keys)

  subnet_id     = aws_subnet.public_subnet[each.key].id
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

Public subnet: direct internet access via the IGW.

Private subnet:

- if `enable_nat = true` → `0.0.0.0/0` routes via NAT → outbound internet works (but no inbound access)
- if `enable_nat = false` → no outbound route → no internet access (cheap mode)

---

## 4) RUNBOOK.md — the safety net

Create `labs/lesson_42/RUNBOOK.md`:

```markdown
# lab42 Terraform Safe Ops: cheap vs full envs, apply/destroy

“This folder = one environment = one state. Never run full from env-cheap.”

⚠️ This runbook assumes:
- single environment per state
- never switching cheap ↔ full on the same state

## Before apply (every time)
- [ ] I am in the correct folder: labs/lesson_42/terraform
- [ ] I am using the intended tfvars file (cheap vs full)
- [ ] allowed_ssh_cidr is my real public IP/32
- [ ] I understand what will be created (terraform plan reviewed)

## Commands (cheap)
terraform fmt -recursive
terraform init
terraform validate
terraform plan -var-file=envs/cheap.tfvars
terraform apply -var-file=envs/cheap.tfvars

## Commands (full)
terraform plan -var-file=envs/full.tfvars
terraform apply -var-file=envs/full.tfvars

## After testing (same day)
terraform destroy -var-file=envs/full.tfvars
# or cheap.tfvars

## If something looks wrong
terraform state list
terraform show
terraform state show <resource_address>

## Emergency stop
If plan shows unexpected destroy:
- STOP
- do NOT apply
- inspect state and addresses

## Strict rule
No manual changes in AWS console unless explicitly documented.

```

---

## 5) State hygiene: what actually need now

### Understand addresses

Terraform tracks resources by addresses like:

- `aws_vpc.main`
- `module.network.aws_subnet.public_subnet["a"]`

If you refactor (e.g., moved to modules, any changes), those addresses change.

If TF can’t map old → new, it wants to recreate.

### Two safe ways to refactor without recreation

1. **`moved` blocks** (best in Terraform 1.1+)
2. `terraform state mv` (manual - `terraform state mv aws_vpc.main module.network.aws_vpc.main`)
- if plan shows “destroy + create” after refactor → need a `moved`/`state mv` step.

---

## 6) Destroy guard habit

Before merging PR that changes network:

- always run `terraform plan` and check:
    - how many destroys?
    - NAT Gateways?
    - EIPs?
    - route tables?

If see unexpected destroys, stop and debug.

---

## Core

- [ ]  Added `env-cheap` and `env-full`.
- [ ]  Added `RUNBOOK.md`.
- [ ]  Run `plan/apply/destroy` with a chosen env without confusion.
- [ ]  Understand why NAT costs money and why “full mode” must be short-lived.
- [ ]  Implemented `enable_full_ha` flag properly (cheap mode actually creates less).
- [ ]  Confirmed cheap mode has **1 NAT or no NAT**, and full mode has 2 NAT.
- [ ]  Practiced `terraform state list` / `state show` and can explain what state is.
- [ ]  Intentionally trigger a refactor issue and explain “why plan wants to recreate”.

---

## Acceptance Criteria

- [ ]  Can safely practice in AWS without leaving expensive resources running.
- [ ]  Know exactly which env I’m deploying (cheap vs full).
- [ ]  Have a written runbook what I can follow when tired.
- [ ]  Can inspect state and understand what Terraform owns.

---
