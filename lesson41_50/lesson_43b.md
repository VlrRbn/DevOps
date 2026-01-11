# lesson_43b

---

# Repaet AWS EC2 on VPC: Bastion + Private Web + Network Proof

**Date:** 2025-01-10

**Topic:** Deploy 2 EC2 instances using Terraform:

- **Bastion** in public subnet (SSH from your IP)
- **Web** in private subnet (SSH only from bastion)
    
    Then prove:
    
- private instance has **outbound internet** via NAT
- private instance has **no inbound from internet**
- SSH hop works: laptop → bastion → web

> Outcome: you can explain cloud networking like a grown-up, not like a YouTube comment section.
> 

---

## Goals

- Add EC2 resources on top of your existing `module.network` outputs.
- Use **existing SGs**: bastion/web from your network module.
- Use **user_data** to install nginx on web.
- Validate routing behavior with simple tests.

---

## Pre-reqs

- You have AWS account ready + you can `terraform apply/destroy`.
- You know your public IP (for `allowed_ssh_cidr = x.x.x.x/32`).
- You already have lesson_40A module outputs like:
    - `public_subnet_ids`, `private_subnet_ids`
    - `security_groups.bastion_sg`, `security_groups.web_sg`

---

## Layout

```
labs/lesson_44/terraform/
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
   ├─ main.tf
   ├─ providers.tf
   ├─ versions.tf
   └─ terraform.tfvars

```

---

## 1) SSH key: local-only, no secrets in git

Generate once:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/lab44_terraform  -C "lab44"

```

---

## 2) Variables (variables.tf)

Add:

```hcl
variable "ssh_key_name" {
  type        = string
  description = "SSH key pair name in AWS to use for EC2 instances"
  default     = "lab44-key"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key"
}

variable "instance_type_bastion" {
  type        = string
  description = "EC2 instance type for bastion host"
  default     = "t3.micro"
}

variable "instance_type_web" {
  type        = string
  description = "EC2 instance type for web server"
  default     = "t3.micro"
}

```

---

## 3) Get Ubuntu AMI (main.tf)

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

```

---

## 4) Upload SSH public key to AWS (main.tf)

```hcl
resource "aws_key_pair" "lab44" {
  key_name   = var.ssh_key_name
  public_key = var.ssh_public_key

  tags = merge(local.tags, {
    Name = "${var.project_name}-keypair"
  })
}

```

---

## 5) User-data for Web (scripts/web-userdata.sh)

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

apt-get update -y
apt-get install -y nginx

echo "lab44 web OK: $(hostname) $(date -u)" > /var/www/html/index.html
systemctl enable --now nginx

```

---

## 6) Create Bastion (public) and Web (private)

### Bastion instance (main.tf)

```hcl
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_bastion
  subnet_id                   = aws_subnet.public_subnet["a"].id
  key_name                    = aws_key_pair.lab44.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-bastion"
    Role = "bastion"
  })
}

```

### Web instance (private)

```hcl
resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_web
  subnet_id                   = aws_subnet.private_subnet["a"].id
  key_name                    = aws_key_pair.lab44.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = false

  user_data = file("${path.module}/scripts/web-userdata.sh")

  tags = merge(local.tags, {
    Name = "${var.project_name}-web"
    Role = "web"
  })
}

```

---

## 7) Outputs (outputs.tf)

```hcl
output "bastion_public_ip" {
  description = "Public IP of Bastion"
  value       = aws_instance.bastion.public_ip
}

output "web_private_ip" {
  description = "Private IP of Web"
  value       = aws_instance.web.private_ip
}

```

---

```bash
Laptop
  |
  | SSH (22) from YOUR_IP/32
  v
[Bastion EC2]  <-- public subnet
     |
     | SSH (22) allowed only from bastion SG
     v
[Web EC2]      <-- private subnet
     |
     | 0.0.0.0/0 via NAT
     v
   Internet

```

---

## 8) Apply

```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan
terraform apply

```

---

## 9) Tests

### A) SSH to bastion

```bash
# WEB_IP="$(terraform output -raw web_private_ip)"
# echo "$WEB_IP"
# echo "$BASTION_IP"

ssh -A -i ~/.ssh/lab44_terraform ubuntu@$(terraform output -raw bastion_public_ip)

```

### B) From bastion → web (private)

On bastion:

```bash
# export WEB_IP="$(terraform output -raw web_private_ip)"
# export BASTION_IP="$(terraform output -raw bastion_public_ip)"

WEB_IP="<web_ip>"
ssh ubuntu@"$WEB_IP"

ssh -i ~/.ssh/lab44_terraform -J ubuntu@$(terraform output -raw bastion_public_ip) ubuntu@"$WEB_IP"

# or connect to Web via Bastion
ssh -i ~/.ssh/lab44_terraform -J ubuntu@"$BASTION_IP" ubuntu@"$WEB_IP"

```

### C) From web: outbound internet via NAT (expected in full mode)

On web:

```bash
curl -I https://httpbin.org/get
# HTTP/2 200

```

### D) From laptop: web should NOT be reachable directly

From your laptop:

```bash
curl -m 3 "http://$WEB_IP" || echo "not reachable from outside (expected)"
# curl: (28) Connection timed out after 3002 milliseconds
# not reachable from outside (expected)

```

### E) Verify nginx running on web (from web itself)

On web:

```bash
curl -s localhost | head
# lab44 web: <web-ip> <date>

systemctl status nginx --no-pager
# Loaded: ... enabled

```

---

## Pitfalls

- SSH fails to bastion → `allowed_ssh_cidr` wrong (must be a real public IP/32).
- Bastion can’t reach web → web SG missing SSH-from-bastion rule.
- Web has no internet → private route table not pointing to NAT (or NAT disabled in cheap mode).
- user_data didn’t run → check:
    
    ```bash
    sudo tail -n 200 /var/log/cloud-init-output.log
    
    ```
    

---

## IMPORTANT - DESTROY

When done testing:

```bash
terraform destroy

```

Don’t leave NAT/instances overnight.

---

## Core

- [ ]  Bastion reachable by SSH.
- [ ]  Web reachable only via bastion.
- [ ]  Web has outbound internet (full mode).
- [ ]  nginx installed via user_data and returns a simple page.
- [ ]  Add second web instance in private subnet B and compare AZ.
- [ ]  Add `Name` tags everywhere and confirm in AWS console.
- [ ]  Add `cheap.tfvars` run and confirm: web has **no** outbound internet (if NAT off) and understand why.