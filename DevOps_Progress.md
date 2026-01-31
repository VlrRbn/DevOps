# 📈 DevOps Progress

| Lesson | Date | Topics Covered |
|-----|------|----------------|
| 1 | 2025-08-19 | Environment Setup and Basic Linux Commands |
| 2 | 2025-08-20 | Nano basics, file ops, permissions, mini-lab project folder |
| 3 | 2025-08-21 | Networking basics, network tools, network diagnostics lab |
| * | 2025-08-22 | Prep evening: revision lesson_01-03, extra practice, repo cleanup |
| 4 | 2025-08-23 | Users & Groups; shared dirs with SGID + default ACL; account policies (chage); sudoers (safe cmds) |
| 5 | 2025-08-25 | Processes & Services - systemd basics; journalctl; custom service+timer; restart policy; transient unit |
| 6 | 2025-08-26 | APT/dpkg search/show/policy; versions; files & owners; holds; snapshot/restore; unattended-upgrades (dry-run) |
| 7 | 2025-08-27 | Bash Scripting (template, rename, backup, logs) |
| 8 | 2025-08-30 | Text processing (grep/sed/awk): log triage (journal & auth), AWK nginx mini-report; tools |
| * | 2025-09-(01-12) | Light study (personal reasons), cheatsheets, minor fixes; prep for Networking lessons |
| 9 | 2025-09-15 | Networking Deep Dive for DevOps (iproute2, ss, tcpdump, DNS, firewall) |
| 10 | 2025-09-18 | Networking (Part 2): NAT / DNAT / netns / UFW Deep |
| 11 | 2025-09-21 | Networking (Part 3): nftables NAT/DNAT + Persistence |
| 12 | 2025-09-23 | Nginx Reverse Proxy + TLS (self-signed) |
| * | 2025-09-(26-30) | Sick leave |
| 13 | 2025-10-01 | Nginx Advanced: Upstreams, Zero-Downtime, Rate-Limits, Security, Caching, JSON Logs |
| 14 | 2025-10-02 | Ansible Fundamentals: Inventory, Playbooks, Roles, Idempotence |
| 15 | 2025-10-04 | Ansible Advanced: Multi-Host, Vault, Rolling Updates, Health Checks |
| 16 | 2025-10-06 | Ansible Role Testing: Molecule + Testinfra + CI |
| * | 2025-10-(09-17) | Extra practice, start new server (project) + CI, add cheatsheets, readthedocs |
| 17 | 2025-10-19 | Monitoring Basics: Prometheus + Node Exporter (+ Grafana) |
| 18 | 2025-10-23 | Alerts & Probes: Alertmanager + Blackbox + Nginx Exporter |
| * | 2025-10-(27-30) | Practice with system administrator "SITA" |
| 19 | 2025-11-04 | Alertmanager Notifications: Email/Telegram, Routing, Silences, Templates |
| 20 | 2025-11-07 | Centralized Logs: Loki + Promtail + Grafana (Nginx JSON) |
| 21 | 2025-11-10 | Grafana as Code: Provisioning Datasources, Dashboards & Alerts |
| * | 2025-11-12 | Practice, cheatsheets |
| 22 | 2025-11-14 | End-to-End Observability: Golden Signals, SLOs & Runbook |
| 23 | 2025-11-19 | Docker Images & Dockerfiles: Build, Tag, Run, Inspect |
| * | 2025-11-20 | Docker Images & Dockerfiles: Upgrade v2 |
| 24 | 2025-11-21 | Docker Compose: Multi-Container App, Networks, Volumes & Health |
| 25 | 2025-11-24 | Docker Multi-Stage Builds & Registry (GitHub Actions CI) |
| 26 | 2025-11-25 | Ansible + Docker: Deploying a Docker Compose Stack to a Host |
| * | 2025-11-27 | Prep evening: Ansible Roles Testing: Molecule + Testinfra + ansible-lint |
| 27 | 2025-11-30 | Kubernetes Intro: Run lab Web + Redis on a Local k8s Cluster |
| 28 | 2025-12-01 | Kubernetes Config: ConfigMap, Secret & Ingress for lab27 Web |
| 29 | 2025-12-03 | Kubernetes Monitoring: Prometheus + kube-state-metrics + Grafana |
| * | 2025-12-07 | Prep evening: K8s CI Polish: Lint, Kustomize & Helm |
| 30 | 2025-12-09 | Kubernetes Observability for lab30-web: App Metrics & Dashboard |
| 31 | 2025-12-11 | K8s Incidents I: CrashLoopBackOff & ImagePullBackOff |
| 32 | 2025-12-14 | K8s Incidents II: OOMKilled, CPU Throttle & QoS |
| 33 | 2025-12-15 | K8s Storage: PVC, PV & Redis StatefulSet |
| 34 | 2025-12-16 | K8s Jobs & CronJobs: One-off Tasks & Redis Backups |
| 35 | 2025-12-18 | K8s RBAC Basics: ServiceAccounts, Roles & RoleBindings |
| 36 | 2025-12-20 | K8s NetworkPolicies: Default Deny & Allow Rules |
| 37 | 2025-12-21 | K8s TLS: Ingress HTTPS with Self-Signed / mkcert |
| * | 2025-12-(22-30) | Anuual leave |
| 38 | 2026-01-01 | K8s cert-manager: Automatic TLS Certificates |
| 39 | 2026-01-02 | Cloud 101: VPC, Subnets, Security Groups & IAM (Terraform-ready) |
| 40 | 2026-01-03 | A: Terraform in Practice: Structure, Variables, tfvars & Modules |
|    |            | B: Terraform: Add Compute on Top of VPC (Bastion + Web) + Connectivity Tests |
| 41 | 2026-01-04 | Terraform CI: fmt/validate + OIDC plan in GitHub Actions |
| 42 | 2026-01-06 | Terraform Safe Ops: cheap vs full envs, state hygiene, apply/destroy runbook |
| 43 | 2026-01-09 | A: GitHub OIDC → AWS IAM Role for Terraform CI from the start |
| * | 2026-01-10 | B: AWS EC2 on VPC: Bastion + Private Web + Network Proof |
| 44 | 2026-01-11 | AWS SSM Session Manager: Access Private EC2 Without SSH (IAM + VPC Endpoints) IAM → SSM → Private EC2 |
| 45 | 2026-01-13 | VPC Interface Endpoints for SSM |
| 46 | 2026-01-14 | SSM Port Forwarding: Access Private Services (Web/DB) Without Opening Ports |
| 47 | 2026-01-16 | EC2 Hardening: IMDSv2 Only + Practical Tests |
| 48 | 2026-01-17 | ALB + 2 Targets: Health Checks, Security Groups, Real Load Balancing |
| 49 | 2026-01-19 | Bake a Golden AMI (Ubuntu 24.04 + Nginx) |
|  | 2026-01-(20-28) | Sick leave |
| 50 | 2026-01-25 | Launch Template + Auto Scaling Group |
| 51 | 2026-01-29 | ASG Scaling Policies & Instance Refresh |
| 52 | 2026-01-31 | Observability & Cost Control (ASG + ALB) |