# 📌 DevOps Learning Journey
 
My journey in DevOps from scratch to first job — daily notes, labs, and mini‑projects.

---

## 📂 Repository structure
```
devops-notes/
 ├─ /lesson01_10/
 │   ├─ lesson_01.md
 │   ├─ lesson_02.md
 │   ├─ lesson_03.md
 │   ├─ lesson_04.md
 │   ├─ lesson_05.md
 │   ├─ lesson_06.md
 │   ├─ lesson_07.md
 │   ├─ lesson_08.md
 │   ├─ lesson_09.md
 │   └─ lesson_10.md
 ├─ /lesson11_20/
 │   ├─ lesson_11.md
 │   ├─ lesson_12.md
 │   └─ lesson_13.md
 ├─ labs/
 │   └─ lesson_05/
 |      ├─ flaky.service
 |      ├─ hello.service
 |      ├─ hello.timer
 |      └─ persistent.conf
 │   └─ lesson_08/
 |      ├─ logs
 |         └─ sample
 |            └─ nginx_access.log
 |      └─ mock
 |         └─ sshd_config
 │   └─ lesson_09/
 |      ├─ captures
 |         ├─ http_20250915_200353.pcap
 |         └─ https_215724.pcap
 |      └─ netns
 |         ├─ run.sh
 |         └─ logs
 │   └─ lesson_10/
 |      ├─ captures
 |         ├─ https_231135.pcap
 |         ├─ https_234049.pcap
 |         └─ https_210356.pcap
 |      └─ netns
 |         ├─ netns-lab10.v1.sh
 |         └─ netns-lab10.v2.sh
│   └─ lesson_11/
 |      ├─ captures
 |         ├─ http_205254.pcap
 |         └─ https_180630.pcap
 |      └─ netns
 |         └─ netns-nft.sh
 ├─ prep_evening/
 │   └─ prep_evening1_en.md
 ├─ cheatsheets/
 |      ├─ backup_and_archives.md
 |      ├─ disks_and_filesystems.md
 |      ├─ files_and_search.md
 |      ├─ logs_and_monitoring.md
 |      ├─ network.md
 |      ├─ packages.md
 |      ├─ processes_and_memory.md
 |      ├─ security_and_hardening.md
 |      ├─ systemd.md
 |      ├─ users_and_permissions.md
 |      └─ variables_and_constructs.md
 ├─ tools/
 |    ├─ apt-dry-upgrade.sh
 |    ├─ backup-dir.sh
 |    ├─ backup-dir.v2.sh
 |    ├─ capture-http.sh
 |    ├─ devops-tail.sh
 |    ├─ devops-tail.v2.sh
 |    ├─ dns-query.sh
 |    ├─ hello.sh
 |    ├─ log-grep.sh
 |    ├─ log-grep.v2.sh
 |    ├─ log-nginx-report.sh
 |    ├─ log-ssh-fail-report.sh
 |    ├─ log-ssh-fail-report.v2.sh
 |    ├─ mkshare.sh
 |    ├─ netns-nft.apply
 |    ├─ net-ports.sh
 |    ├─ nft-save-restore.sh
 |    ├─ pkg-restore.sh
 |    ├─ pkg-snapshot.sh
 |    ├─ rename-ext.sh
 |    ├─ rename-ext.v2.sh
 │    └─ _template.sh
 ├─ DevOps_Progress.md
 └─ README.md
```

> If some files are missing yet — they’ll be added later.

---

## 📅 Calendar
| Day | Topic | Materials |
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
| **Lesson 13** | Nginx Advanced: Upstreams, Zero-Downtime, Rate-Limits, Security, Caching, JSON Logs | [Materials_13](lesson11_20/lesson_13.md) |
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
