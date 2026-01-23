# lesson_49

---

# Packer: Bake a Golden AMI (Ubuntu 24.04 + Nginx)

**Date:** 2025-01-19

**Topic:** Build a **golden AMI** using Packer and integrate it with Terraform to replace heavy user-data.

---

## Why This Matters

**User-data is a bootstrap crutch.**

- Slow boot
- Race conditions (cloud-init, network, apt)
- Poor scalability

**Baked AMIs are control.**

- Fast EC2 startup
- Deterministic environment
- Required for ASG / Launch Templates

---

**User data**:

- runs on **every boot**
- depends on networking
- can fail while the EC2 still shows as “running”

**AMI**:

- built **once**
- validated ahead of time
- the instance is either correct, or it won’t come up properly

---

## Architecture

```
Packer
 └── AMI (Ubuntu 24.04 + nginx + web page)
        └── Terraform
              └── EC2 web_a / web_b
                    └── ALB Target Group

```

**Important:**

- AMI = OS + software + files
- Network, ALB, SG, IAM, SSM = Terraform, **NOT AMI**

---

## Goals / Acceptance Criteria

- [ ]  Packer build produces an AMI
- [ ]  AMI contains nginx and `/var/www/html/index.html`
- [ ]  EC2 instances boot without heavy user-data
- [ ]  ALB successfully balances baked instances
- [ ]  `curl` shows different backend hostnames

---

## Project Layout

```
lesson41_50/lesson_49/
├── packer/
│   ├── web.pkr.hcl
│   └── scripts/
│       ├── disable-nginx.sh
│       ├── install-nginx.sh
│       ├── render-index.service
│       ├── render-index.sh
│       ├── setup-render.sh
│       └── web-content.sh
└── lesson_49.md

```

---

## 1) Install Packer

On Ubuntu 24.04:

```bash
sudo apt update
sudo apt install -y packer
packer version   # Packer v1.14.3

```

---

## 2) Provisioning Scripts

### `scripts/install-nginx.sh`

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

if ! dpkg -s nginx >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y nginx
fi

systemctl enable nginx
```

**Why this matters:**

- idempotent
- safe for rebuilds
- no hidden side effects

---

### `scripts/web-content.sh`

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p /var/www/html

cat >/var/www/html/index.html <<'EOF'
<h1>Web baked by Packer</h1>
<p>Hostname: __HOSTNAME__</p>
<p>InstanceId: __INSTANCE_ID__</p>
EOF
```

> hostname is resolved at instance boot, not at bake time — this is expected and correct.
> 

Why this is good:

- each instance is unique
- it’s easy to verify the ALB
- it demonstrates immutability

## What’s important to understand — these scripts:

- run **once**
- affect **every future EC2 instance**
- must be **predictable**
- should **fail the build** if something is wrong

---

## 3) Packer Template (`web.pkr.hcl`)

```hcl
packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.10"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "ami_name_prefix" {
  type    = string
  default = "lab49-web"
}

source "amazon-ebs" "web" {
  region        = var.aws_region
  instance_type = "t3.micro"
  ssh_username  = "ubuntu"

  ami_name = "${var.ami_name_prefix}-${formatdate("YYYYMMDD-hhmm", timestamp())}"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  tags = {
    Project = "DevOps"
    Role    = "web"
    Lesson  = "49"
  }
}

build {
  sources = ["source.amazon-ebs.web"]

  provisioner "shell" {
    script          = "scripts/install-nginx.sh"
    execute_command = "sudo -n bash '{{.Path}}'"
  }

#  provisioner "shell" {
#    script          = "scripts/disable-nginx.sh"
#    execute_command = "sudo -n bash '{{.Path}}'"
#  }

  provisioner "shell" {
    script          = "scripts/web-content.sh"
    execute_command = "sudo -n bash '{{.Path}}'"
  }

  provisioner "file" {
    source      = "scripts/render-index.sh"
    destination = "/tmp/render-index.sh"
  }

  provisioner "file" {
    source      = "scripts/render-index.service"
    destination = "/tmp/render-index.service"
  }

 # provisioner "shell" {
 #   script           = "scripts/setup-render.sh"
 #   environment_vars = [
 #     "AMI_VERSION=${var.ami_name_prefix}",
 #     "BUILD_TIME=${timestamp()}"
 #   ]
 # }
}

```

---

## `scripts/render-index.sh`

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# IMDSv2 token
TOKEN="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)"

HN="$(hostname)"
IID="unknown"
# AMI_VERSION="unknown"
# BUILD_TIME="unknown"

if [[ -n "${TOKEN:-}" ]]; then
  IID="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || true)"
fi

# if [[ -f /etc/web-build/meta.env ]]; then
#  # shellcheck disable=SC1091
#  source /etc/web-build/meta.env
# fi

sed -i \
#  -e "s/__AMI_VERSION__/${AMI_VERSION}/g" \
#  -e "s/__BUILD_TIME__/${BUILD_TIME}/g" \
  -e "s/__HOSTNAME__/${HN}/g" \
  -e "s/__INSTANCE_ID__/${IID}/g" \
  /var/www/html/index.html
```

---

## `scripts/render-index.service`

```bash
[Unit]
Description=Render nginx index.html with runtime metadata
ConditionPathExists=/var/www/html/index.html
After=network-online.target nginx.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/render-index.sh

[Install]
WantedBy=multi-user.target
```

---

## `scripts/setup-render.sh`

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# AMI_VERSION="${AMI_VERSION:-unknown}"
# BUILD_TIME="${BUILD_TIME:-unknown}"

# sudo mkdir -p /etc/web-build
sudo install -d -m 0755 /usr/local/bin
sudo install -m 0755 /tmp/render-index.sh /usr/local/bin/render-index.sh
sudo install -m 0644 /tmp/render-index.service /etc/systemd/system/render-index.service
# echo "AMI_VERSION=${AMI_VERSION}" | sudo tee /etc/web-build/meta.env >/dev/null
# echo "BUILD_TIME=${BUILD_TIME}" | sudo tee -a /etc/web-build/meta.env >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable render-index.service
```

---

## 4) Build the AMI

```bash
cd labs/lesson_49/packer
packer init .
packer fmt .
packer validate .
packer build .

# or better in local
PACKER_LOG=1 packer build .

```

You’ll see:

- SSH commands
- exit codes
- timings
- which provisioner failed

Expected result:

```
--> amazon-ebs.web: AMIs were created:
eu-west-1: ami-02513f048f01c79f5

```

Save this AMI ID — it will be used in Terraform.

## What happens during `packer build`

Packer runs a **strict, well-defined workflow**:

1. **Validate**
    - syntax checks
    - plugins
    - variables
2. **Find base AMI**
    - runs `source_ami_filter`
    - picks *one* AMI
3. **Create temporary resources**
    - EC2 instance
    - temporary security group
    - temporary SSH key
4. **Provisioning**
    - connect via SSH
    - run `install-nginx.sh`
    - run `web-content.sh`
5. **AMI creation**
    - shut down the instance
    - snapshot the root volume
    - register the AMI
6. **Cleanup**
    - terminate the EC2
    - delete the security group
    - delete the SSH key

---

## 5) Terraform Integration

### variables.tf

```hcl
variable "web_ami_id" {
  type        = string
  description = "Baked web AMI from Packer"
}

```

### terraform.tfvars

```hcl
web_ami_id = "ami-0abc123..."

```

### EC2 resource

```hcl
 web_ami_id = var.web_ami_id
 
```

---

## 6) Minimal User-Data (Important)

```bash
#!/bin/bash
echo "boot ok" > /tmp/boot.txt

```

### Why this matters

- user data runs on **every boot**
- an AMI is built **once**
- if you need Nginx → it **must already be in the AMI**

That’s the key principle.

---

## 7) Validation through ALB

```bash
ALB="$(terraform output -raw alb_dns_name)"

for i in {1..10}; do
  curl -s "http://$ALB" | grep Hostname
done

```

Expected output:

```
Hostname: ip-10-30-11-179
Hostname: ip-10-30-11-173
```

This confirms:

- ALB health checks pass
- instances are baked correctly
- load balancing works

---

## Common Pitfalls

- Baking SSM / Terraform / CloudWatch into AMI
- Using `latest` without filters
- Running `apt upgrade` during bake
- Hardcoding AMI IDs inside modules

---

## Security Checklist

- No secrets in AMI
- No SSH keys baked
- No IAM credentials baked
- Minimal OS surface
- Deterministic boot behavior

---

## Drills

### Drill 1 — Rebuild Cycle

Goal: build muscle memory for: ***change → bake → deploy → verify.***

1. Make a small change in the AMI
2. Inject build-time metadata (once)
3. Pass build-time values from Packer
4. Rebuild the AMI
5. Deploy the new AMI via Terraform
6. Prove it through the ALB (mandatory)

From `ssm-proxy`:

```bash
aws ssm start-session --target <proxy-instance-id>

ALB="<internal-alb-dns>"

for i in {1..20}; do
  curl -s -H 'Connection: close' "http://$ALB" \
    | grep -E 'AMI Version|Built At|Hostname|InstanceId'
  echo "----"
done
```

## Acceptance Criteria (Drill 1)

- [ ]  A new AMI is created
- [ ]  Terraform uses **only** the new AMI
- [ ]  The ALB serves the new version
- [ ]  No changes were made to user data
- [ ]  No “manual fixes”

---

### Drill 2 — Failure Simulation

Goal: don’t panic when everything turns red — follow the plan:

***change → bake → deploy → observe → rollback/fix → bake → deploy.***

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

systemctl disable --now nginx
systemctl mask nginx

# then add in web.pkr
  provisioner "shell" {
    script          = "scripts/disable-nginx.sh"
    execute_command = "sudo -n bash '{{.Path}}'"
  }
```

1. Break the AMI so that Nginx **doesn’t start on boot**.
2. Rebuild the AMI.
3. Roll it out via Terraform.
4. Observe the ALB targets become unhealthy / see `503`.
5. Fix it.
6. Rebuild + redeploy.
7. Confirm everything is healthy again.

From `ssm-proxy`:

```bash
aws ssm start-session --target <proxy-instance-id>

ALB="<internal-alb-dns>"

for i in {1..10}; do
  curl -s -m 3 -H 'Connection: close' "http://$ALB" | head -n 2
  echo "----"
done

aws elbv2 describe-target-groups \
  --names lab48-web-tg \
  --query 'TargetGroups[0].TargetGroupArn' --output text

TG_ARN="arn:aws:elasticloadbalancing:eu-west-1..."

aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN"

```

Expected outcomes can include:

- `503 Service Unavailable` (if there are no healthy targets) (what you’re see now)
- or hangs/empty responses (if health checks don’t pass)

```bash
aws elbv2 describe-target-groups \
  --names lab48-web-tg \
  --query 'TargetGroups[0].TargetGroupArn' --output text

TG_ARN="arn:aws:elasticloadbalancing:eu-west-1..."

aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN"

```

You should expect `unhealthy` with reasons like:

- `Target.Timeout`
- `Target.FailedHealthChecks` (what you’re see now)

## Acceptance Criteria (Drill 2)

- [ ]  **Intentionally** broke the boot behavior
- [ ]  The ALB targets became unhealthy / you saw a `503`
- [ ]  Confirmed the cause via `systemctl status nginx`
- [ ]  Fixed it by building a new AMI (not by patching the instance manually)
- [ ]  The ALB is healthy again

---

### Drill 3 — Immutability Check

```bash
sudo sed -i 's/Web baked by Packer/HACKED BY MY HANDS/g' /var/www/html/index.html
sudo systemctl reload nginx

```

1. SSM into a web instance
2. “Fix” something manually (intentionally the wrong approach)
3. Proof (via the ALB)
4. Terminate the instance
5. Reality check (repeat the proof after ~ 30 seconds)
6. Observe that the changes disappear
7. Realization (this is the key)

## Acceptance Criteria (Drill 3)

- [ ]  The manual change showed up
- [ ]  After termination, it disappeared
- [ ]  The AMI remained the source of truth
- [ ]  You **didn’t try to keep fixing it manually afterward**

---

## Summary

This lesson introduced the concept of a baked AMI as a deployable artifact.

An immutable AMI was built using Packer, validated through an Application Load Balancer, and integrated with Terraform without relying on heavy user data.

The key distinction demonstrated is the separation between **build-time** and **boot-time** concerns:

- software and files belong in the AMI
- infrastructure and networking belong in Terraform
- user data should be minimal
- recovery means **rebuild and redeploy**, not SSH and patch

If an instance is wrong, it should not be fixed — it should be **replaced**. Manual changes are not solutions.

Failures were handled by rebuilding and redeploying the AMI rather than modifying running instances, reinforcing the immutable infrastructure model.

This approach enables deterministic boots, predictable rollouts, and straightforward recovery.
