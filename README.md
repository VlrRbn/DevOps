# 📌 DevOps Learning Journey
 
My journey in DevOps from scratch to first job — daily notes, labs, and mini‑projects.

---

## 📂 Repository structure
```
devops-notes/
 ├─ ansible/
 ├─ cheatsheets/
 ├─ labs/
 ├─ /lesson01_10/
 ├─ /lesson11_20/
 ├─ /lesson21_30/
 ├─ /lesson31_40/
 ├─ /lesson41_50/
 ├─ /lesson51_60/
 ├─ runbook/
 ├─ templates/
 ├─ tools/
 ├─ DevOps_Progress.md
 └─ README.md
```

> If some files are missing yet — they'll be added later.

---

## 📅 Calendar
| Lesson | Topic | Materials | README |
|-----|-------|-----------|-----------|
| **Lesson 1** | Environment Setup and Basic Linux Commands | [Materials_1](lesson01_10/lesson_01.md) |
| **Lesson 2** | Nano basics; file ops; permissions; mini-lab project folder | [Materials_2](lesson01_10/lesson_02.md) |
| **Lesson 3** | Networking basics; network tools; network diagnostics lab | [Materials_3](lesson01_10/lesson_03.md) |
| **Lesson 4** | Users & Groups; shared dirs with SGID + default ACL; account policies (chage); sudoers (safe cmds) | [Materials_4](lesson01_10/lesson_04.md) | 
| **Lesson 5** | Processes & Services — systemd basics; journalctl; custom service+timer; restart policy; transient unit | [Materials_5](lesson01_10/lesson_05.md) |
| **Lesson 6** | APT/dpkg — search/show/policy; versions; files & owners; holds; snapshot/restore (dry); unattended-upgrades (dry-run) | [Materials_6](lesson01_10/lesson_06.md) |
| **Lesson 7** | Bash Scripting (template, rename, backup, logs) | [Materials_7](lesson01_10/lesson_07.md) |
| **Lesson 8** | Text processing (grep/sed/awk): log triage (journal & auth), AWK nginx mini-report; tools | [Materials_8](lesson01_10/lesson_08.md) |
| **Lesson 9** | Networking Deep Dive (ip/ss, DNS, tcpdump, UFW, netns) | [Materials_9](lesson01_10/lesson_09.md) |
| **Lesson 10** | Networking (Part 2): NAT / DNAT / netns / UFW Deep | [Materials_10](lesson01_10/lesson_10.md) |
| **Lesson 11** | Networking (Part 3): nftables NAT/DNAT + Persistence | [Materials_11](lesson11_20/lesson_11.md) |
| **Lesson 12** | Nginx Reverse Proxy + TLS (self-signed) | [Materials_12](lesson11_20/lesson_12.md) |
| **Lesson 13** | Nginx Advanced: Upstreams, Zero-Downtime, Rate-Limits, Security, Caching, JSON Logs | [Materials_13](lesson11_20/lesson_13_v1.md) |
| **Lesson 14** | Ansible Fundamentals: Inventory, Playbooks, Roles, Idempotence | [Materials_14](lesson11_20/lesson_14.md) |
| **Lesson 15** | Ansible Advanced: Multi-Host, Vault, Rolling Updates, Health Checks | [Materials_15](lesson11_20/lesson_15.md) |
| **Lesson 16** | Ansible Role Testing: Molecule + Testinfra + CI | [Materials_16](lesson11_20/lesson_16.md) |
| **Lesson 17** | Monitoring Basics: Prometheus + Node Exporter (+ Grafana) | [Materials_17](lesson11_20/lesson_17.md) |
| **Lesson 18** | Alerts & Probes: Alertmanager + Blackbox + Nginx Exporter | [Materials_18](lesson11_20/lesson_18.md) |
| **Lesson 19** | Alertmanager Notifications: Email/Telegram, Routing, Silences, Templates | [Materials_19](lesson11_20/lesson_19.md) |
| **Lesson 20** | Centralized Logs: Loki + Promtail + Grafana (Nginx JSON) | [Materials_20](lesson11_20/lesson_20.md) |
| **Lesson 21** | Grafana as Code: Provisioning Datasources, Dashboards & Alerts | [Materials_21](lesson21_30/lesson_21.md) |
| **Lesson 22** | End-to-End Observability: Golden Signals, SLOs & Runbook | [Materials_22](lesson21_30/lesson_22.md) |
| **Lesson 23** | Docker Images & Dockerfiles: Build, Tag, Run, Inspect | [Materials_23](lesson21_30/lesson_23.md) |
| **Lesson 24** | Docker Compose: Multi-Container App, Networks, Volumes & Health | [Materials_24](lesson21_30/lesson_24.md) |
| **Lesson 25** | Docker Multi-Stage Builds & Registry (GitHub Actions CI) | [Materials_25](lesson21_30/lesson_25.md) |
| **Lesson 26** | Ansible + Docker: Deploying a Docker Compose Stack to a Host | [Materials_26](lesson21_30/lesson_26.md) |
| **Lesson 27** | Kubernetes Intro: Run lab Web + Redis on a Local k8s Cluster | [Materials_27](lesson21_30/lesson_27.md) |
| **Lesson 28** | Kubernetes Config: ConfigMap, Secret & Ingress | [Materials_28](lesson21_30/lesson_28.md) |
| **Lesson 29** | Kubernetes Monitoring: Prometheus + kube-state-metrics + Grafana | [Materials_29](lesson21_30/lesson_29.md) |
| **Lesson 30** | Kubernetes Observability for lab27-web: App Metrics & Dashboard | [Materials_30](lesson21_30/lesson_30.md) |
| **Lesson 31** | K8s Incidents I: CrashLoopBackOff & ImagePullBackOff | [Materials_31](lesson31_40/lesson_31.md) |
| **Lesson 32** | K8s Incidents II: OOMKilled, CPU Throttle & QoS | [Materials_32](lesson31_40/lesson_32.md) |
| **Lesson 33** | K8s Storage: PVC, PV & Redis StatefulSet | [Materials_33](lesson31_40/lesson_33.md) |
| **Lesson 34** | K8s Jobs & CronJobs: One-off Tasks & Redis Backups | [Materials_34](lesson31_40/lesson_34.md) |
| **Lesson 35** | K8s RBAC Basics: ServiceAccounts, Roles & RoleBindings | [Materials_35](lesson31_40/lesson_35.md) |
| **Lesson 36** | K8s NetworkPolicies: Default Deny & Allow Rules | [Materials_36](lesson31_40/lesson_36.md) |
| **Lesson 37** | K8s TLS: Ingress HTTPS with Self-Signed / mkcert | [Materials_37](lesson31_40/lesson_37.md) |
| **Lesson 38** | K8s cert-manager: Automatic TLS Certificates | [Materials_38](lesson31_40/lesson_38.md) |
| **Lesson 39** | Cloud 101: VPC, Subnets, Security Groups & IAM (Terraform-ready) | [Materials_39](lesson31_40/lesson_39.md) |
| **Lesson 40a** | A: Terraform in Practice: Structure, Variables, tfvars & Modules | [Materials_40a](lesson31_40/lesson_40a.md) |
| **Lesson 40b** | B: Terraform: Add Compute on Top of VPC (Bastion + Web) + Connectivity Tests | [Materials_40b](lesson31_40/lesson_40b.md)|
| **Lesson 41** | Terraform CI: fmt/validate + plan in GitHub Actions | [Materials_41](lesson41_50/lesson_41.md) |
| **Lesson 42** | Terraform Safe Ops: cheap vs full envs, state hygiene | [Materials_42](lesson41_50/lesson_42.md) |
| **Lesson 43a** | GitHub OIDC → AWS IAM Role for Terraform CI from the start | [Materials_43a](lesson41_50/lesson_43a.md) |
| **Lesson 43b** | AWS EC2 on VPC: Bastion + Private Web + Network Proof | [Materials_43b](lesson41_50/lesson_43b.md) |
| **Lesson 44** | AWS SSM Session Manager: Access Private EC2 Without SSH | [Materials_44](lesson41_50/lesson_44.md) |
| **Lesson 45** | VPC Interface Endpoints for SSM | [Materials_45](lesson41_50/lesson_45.md) |
| **Lesson 46** | SSM Port Forwarding: Access Private Services (Web/DB) Without Opening Ports | [Materials_46](lesson41_50/lesson_46.md) |
| **Lesson 47** | EC2 Hardening: IMDSv2 Only + Practical Tests | [Materials_47](lesson41_50/lesson_47.md) |
| **Lesson 48** | ALB + 2 Targets: Health Checks, Security Groups, Real Load Balancing | [Materials_48](lesson41_50/lesson_48.md) |
| **Lesson 49** | Bake a Golden AMI (Ubuntu 24.04 + Nginx) | [Materials_49](lesson41_50/lesson_49/lesson_49.md) | [Readme](lesson41_50/lesson_49/README.md) |
| **Lesson 50** | Launch Template + Auto Scaling Group | [Materials_50](lesson41_50/lesson_50/lesson_50.md) | [Readme](lesson41_50/lesson_50/README.md) |
| **Lesson 51** | ASG Scaling Policies & Instance Refresh | [Materials_51](lesson51_60/lesson_51/lesson_51.md) | [Readme](lesson51_60/lesson_51/README.md) |
| **Lesson 52** | Observability & Cost Control (ASG + ALB) | [Materials_52](lesson51_60/lesson_52/lesson_52.md) | [Readme](lesson51_60/lesson_52/README.md) |
| **Lesson 53** | ALB Deep Dive: Health Checks, Failure Modes & Traffic Control | [Materials_53](lesson51_60/lesson_53/lesson_53.md) | [Readme](lesson51_60/lesson_53/README.md) |
| **Lesson 54** | Blue/Green Deployments with ALB + ASG | [Materials_54](lesson51_60/lesson_54/lesson_54.md) | [Readme](lesson51_60/lesson_54/README.md) |
| **Lesson 55** | Rolling Deployments & Safe Rollback (ASG Instance Refresh as a Deployment Engine) | [Materials_55](lesson51_60/lesson_55/lesson_55.md) | [Readme](lesson51_60/lesson_55/README.md) |
| **Lesson 56** | Guardrailed Deployments (Auto Rollback, Checkpoints, Skip Matching) | [Materials_56](lesson51_60/lesson_56/lesson_56.md) | [Readme](lesson51_60/lesson_56/README.md) |
---

## How to use
- Each lesson: **Goals → Practice → Mini-lab → Summary** in `lesson_N.md`.
- Labs under `labs/lesson_N/...`, scripts under `tools/`.
- If copied from `/etc` or `/usr/local/bin` with sudo, fix ownership before commit:
  ```bash
  sudo chown -R "$(id -un)":"$(id -gn)" labs tools
  ```
- Make scripts executable:
  ```bash
  chmod +x tools/*.sh
  ```
---

## 📈 Progress
- Daily log: [DevOps Progress](DevOps_Progress.md)
---

## 🎯 Goal
Learn Linux, networking, scripting, CI/CD, containers, cloud, and automation to get a DevOps job.  
