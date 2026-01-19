# lesson_49

---

# Packer: Bake a Golden AMI (Ubuntu 24.04 + Nginx)

**Date:** 2025-01-19

**Topic:** Build a **golden AMI** using Packer and integrate it with Terraform to replace heavy user-data.

---

## Why This Matters (Short & Honest)

**User-data is a bootstrap crutch.**

- Slow boot
- Race conditions (cloud-init, network, apt)
- Poor scalability

**Baked AMIs are control.**

- Fast EC2 startup
- Deterministic environment
- Required for ASG / Launch Templates

---

## Architecture

```
Packer
 └── AMI (Ubuntu 24.04 + nginx + web page)
        └── Terraform
              └── EC2 web_a / web_b
                    └── ALB Target Group

```

**Important rule:**

- AMI = OS + software + files
- Network, ALB, SG, IAM, SSM = Terraform, not AMI

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
labs/lesson_49/
├── packer/
│   ├── web.pkr.hcl
│   ├── variables.pkr.hcl
│   └── scripts/
│       ├── install-nginx.sh
│       └── web-content.sh
└── lesson_49.md

```

---
