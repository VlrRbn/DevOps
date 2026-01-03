# lesson_40b

---

# Terraform: Add Compute on Top of VPC (Bastion + Web) + Connectivity Tests

**Date:** 2025-01-03

**Topic:** Reuse existing lesson_40 network stack (VPC + subnets + NAT + SGs) and add:

- **Bastion EC2** in a public subnet
- **Web EC2** in a private subnet
- basic **user-data** provisioning
- **connectivity checks** (SSH via bastion, outbound internet via NAT, inbound rules)

---

## Goals

- Launch EC2 instances in the right subnets:
    - Bastion in **public** subnet
    - Web in **private** subnet
- Use your existing security groups:
    - Bastion SG: SSH from `allowed_ssh_cidr`
    - Web SG: SSH only from Bastion SG, HTTP/HTTPS public rules (we’ll not expose it directly yet)
- Validate the network behavior:
    - SSH to bastion from your machine
    - SSH from bastion to web (private)
    - Web can reach internet (via NAT) but is not reachable from internet directly
- Learn the Terraform pattern:
    - `data "aws_ami"` for Ubuntu
    - `aws_key_pair` + local SSH key usage
    - outputs for instance IPs

---

## Preconditions

- Lesson_40 Terraform applies cleanly (VPC, subnets, IGW, NAT, SGs).
- Have an SSH keypair locally (no secrets in git).

Create (if needed):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/lab40_terraform -C "lab40"

```

Public key: `~/.ssh/lab40_terraform.pub`

---

## Layout

```
labs/lesson_40/
├─ docker/
│  └─ docker-compose.yaml
└─ terraform/
   ├─ main.tf                # + new EC2 resources
   ├─ variables.tf           # add key_name/public_key_path instance types
   ├─ outputs.tf             # add bastion public IP + web private IP
   ├─ terraform.tfstate
   ├─ envs/
   │  └─ dev.tfvars
   └─ modules/
      └─ network/
         ├─ main.tf          # VPC, subnets, SGs (moved from lesson_39)
         ├─ variables.tf     # module inputs
         ├─ outputs.tf       # vpc_id, subnet_ids, sg_ids
         └─ scripts/
            └─ web-userdata.sh

```

---

## 1) Data: pick an Ubuntu AMI (add to main.tf)

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners = ["099720109477"] # Canonical

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

## 2) SSH key pair in AWS (add to main.tf)

```hcl
resource "aws_key_pair" "lab40" {
  key_name   = var.key_name
  public_key = file(pathexpand(var.public_key_path))

  tags = merge(local.tags, {
    Name = "${var.project_name}-keypair"
  })  
}

```

---

## 3) Bastion EC2 (public subnet)

```hcl
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_bastion
  subnet_id                   = aws_subnet.public_subnet["a"].id
  key_name                    = aws_key_pair.lab40.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-bastion"
    Role = "bastion"
  })
}
```

---

## 4) Web EC2 (private subnet) + user-data

Create a tiny user-data script that starts nginx:

`scripts/web-userdata.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

apt-get update -y
apt-get install -y nginx

echo "lab40 web: $(hostname) $(date -u)" > /var/www/html/index.html
systemctl enable --now nginx

```

In Terraform:

```hcl
resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_web
  subnet_id                   = aws_subnet.private_subnet["a"].id
  key_name                    = aws_key_pair.lab40.key_name
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

## 5) Outputs (append to outputs.tf)

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

## 6) New variables (append to variables.tf)

Add:

```hcl
variable "key_name" {
  type        = string
  description = "SSH key pair name in AWS to use for EC2 instances"
  default     = "lab40-key"
}

variable "public_key_path" {
  type        = string
  description = "Path to the public key file for the SSH key pair"
  default     = "~/.ssh/lab40_terraform.pub"
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

## 7) Apply and test

### Terraform

```bash
terraform fmt
terraform validate
terraform plan
terraform apply

# tflocal init
# tflocal plan -var-file=envs/dev.tfvars
# tflocal apply -var-file=envs/dev.tfvars

# tflocal state show module.network.aws_instance.bastion | egrep "arn|id|public_ip|subnet_id|vpc_security_group_ids"

```

### Connectivity checks

1. SSH from your laptop → bastion:

```bash
ssh -i ~/.ssh/lab40_terraform ubuntu@$(terraform output -raw bastion_public_ip)

```

2. From bastion → web (private IP):

```bash
WEB_IP="$(terraform output -raw web_private_ip)"
ssh -i ~/.ssh/lab40_terraform ubuntu@"$WEB_IP"

```

3. From web instance: internet access should work (NAT)

```bash
curl -I https://google.com

```

4. From your laptop: web should NOT be directly reachable (private subnet)

```bash
curl -m 3 http://<web_private_ip> || echo "not reachable from outside (expected)"

```

---

## Core

- [ ]  Bastion in public subnet, SSH reachable from my machine
- [ ]  Web in private subnet, SSH reachable only via bastion
- [ ]  Web has outbound internet via NAT
- [ ]  Outputs show public IP and private IP
- [ ]  Add a second web instance in private subnet B and compare AZs
- [ ]  Add a small `null_resource` with remote-exec (optional) and see why user_data is usually better
- [ ]  Add a “destroy checklist” and clean teardown

---

## Pitfalls

- If SSH fails: `allowed_ssh_cidr` probably wrong (must be a real public IP + `/32`)
- If web has no internet: check private route table → NAT, and NAT is in a public subnet with IGW route
- If user-data didn’t run: check `/var/log/cloud-init-output.log` on the instance
- Don’t commit private keys
