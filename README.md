# 📌 DevOps Learning Journey
 
My journey in DevOps from scratch to first job — daily notes, labs, and mini‑projects.

---

## 📂 Repository structure
```
devops-notes/
 ├─ ansible_molecule
 ├─ ansible_practice
 ├─ cheatsheets/
 ├─ labs/
 ├─ /lesson01_10/
 ├─ /lesson11_20/
 ├─ /lesson21_30/
 ├─ prep_evening/
 ├─ tools/
 ├─ DevOps_Progress.md
 └─ README.md
```

> If some files are missing yet — they’ll be added later.

---

## 📅 Calendar
| Lesson | Topic | Materials |
|-----|-------|-----------|
| **Lesson 1** | Environment Setup and Basic Linux Commands | [Materials_1](lesson01_10/lesson_01.md) |
| **Lesson 2** | Nano basics; file ops; permissions; mini-lab project folder | [Materials_2](lesson01_10/lesson_02.md) |
| **Lesson 3** | Networking basics; network tools; network diagnostics lab | [Materials_3](lesson01_10/lesson_03.md) |
| **Lesson !** | Prep evening: revision Day1–3; extra practice | [Materials_EV](prep_evening/prep_evening1_en.md) |
| **Lesson 4** | Users & Groups; shared dirs with SGID + default ACL; account policies (chage); sudoers (safe cmds) | [Materials_4](lesson01_10/lesson_04.md) | 
| **Lesson 5** | Processes & Services — systemd basics; journalctl; custom service+timer; restart policy; transient unit | [Materials_5](lesson01_10/lesson_05.md) |
| **Lesson 6** | APT/dpkg — search/show/policy; versions; files & owners; holds; snapshot/restore (dry); unattended-upgrades (dry-run) | [Materials_6](lesson01_10/lesson_06.md) |
| **Lesson 7** | Bash Scripting (template, rename, backup, logs) | [Materials_7](lesson01_10/lesson_07.md) |
| **Lesson 8** | Text processing (grep/sed/awk): log triage (journal & auth), AWK nginx mini-report; tools | [Materials_8](lesson01_10/lesson_08.md) |
| **Lesson !** | Extra practice, repo cleanup, cheat sheets |
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
---

## How to use
- Each lesson: **Goals → Practice → Mini-lab → Summary** in `lesson_N.md`.
- Labs under `labs/lesson_N/…`, scripts under `tools/`.
- If copied from `/etc` or `/usr/local/bin` with sudo, fix ownership before commit:
  ```bash
  sudo chown -R "$(id -un)":"$(id -gn)" labs tools
  ```
- Make scripts executable:
  ```bash
  chmod +x tools/*.sh
  ```
---

## Example — lesson_05 quick check
```bash
sudo systemctl enable --now hello.timer
systemctl list-timers --all | grep hello
journalctl -u hello.service -n 10 --no-pager
```

## 📈 Progress
- Daily log: [DevOps Progress](DevOps_Progress.md)

---

## 🎯 Goal
Learn Linux, networking, scripting, CI/CD, containers, cloud, and automation to get a DevOps engineer job.  
