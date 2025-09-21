# 📌 DevOps Learning Journey
 
My journey in DevOps from scratch to first job — daily notes, labs, and mini‑projects.

---

## 📂 Repository structure
```
devops-notes/
 ├─ Day1/
 │   └─ day1_en.md
 ├─ Day2/
 │   └─ day2_en.md
 ├─ Day3/
 │   └─ day3_en.md
 ├─ Day4/
 │   └─ day4_en.md
 ├─ Day5/
 │   └─ day5_en.md
 ├─ Day6/
 │   └─ day6_en.md
 ├─ Day7/
 │   └─ day7_en.md
 ├─ Day8/
 │   └─ day8_en.md
 ├─ Day9/
 │   └─ day9_en.md
├─ Day9/
 │   └─ day10_en.md
 ├─ labs/
 │   └─ day5/
 |      ├─ flaky.service
 |      ├─ hello.service
 |      ├─ hello.timer
 |      └─ persistent.conf
 │   └─ day8/
 |      ├─ logs
 |         └─ sample
 |            └─ nginx_access.log
 |      └─ mock
 |         └─ sshd_config
 │   └─ day9/
 |      ├─ captures
 |         ├─ http_20250915_200353.pcap
 |         └─ https_215724.pcap
 |      └─ netns
 |         ├─ run.sh
 |         └─ logs
 │   └─ day10/
 |      ├─ captures
 |         ├─ https_231135.pcap
 |         ├─ https_234049.pcap
 |         └─ https_210356.pcap
 |      └─ netns
 |         ├─ netns-lab10.v1.sh
 |         └─ netns-lab10.v2.sh
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
 |    ├─ net-ports.sh
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
| **Day 1** | Environment Setup and Basic Linux Commands | [Materials_1](Day1/day1_en.md) |
| **Day 2** | Nano basics; file ops; permissions; mini-lab project folder | [Materials_2](Day2/day2_en.md) |
| **Day 3** | Networking basics; network tools; network diagnostics lab | [Materials_3](Day3/day3_en.md) |
| **Day !** | Prep evening: revision Day1–3; extra practice | [Materials_EV](prep_evening/prep_evening1_en.md) |
| **Day 4** | Users & Groups; shared dirs with SGID + default ACL; account policies (chage); sudoers (safe cmds) | [Materials_4](Day4/day4_en.md) | 
| **Day 5** | Processes & Services — systemd basics; journalctl; custom service+timer; restart policy; transient unit | [Materials_5](Day5/day5_en.md) |
| **Day 6** | APT/dpkg — search/show/policy; versions; files & owners; holds; snapshot/restore (dry); unattended-upgrades (dry-run) | [Materials_6](Day6/day6_en.md) |
| **Day 7** | Bash Scripting (template, rename, backup, logs) | [Materials_7](Day7/day7_en.md) |
| **Day 8** | Text processing (grep/sed/awk): log triage (journal & auth), AWK nginx mini-report; tools | [Materials_8](Day8/day8_en.md) |
| **Day !** | Extra practice, repo cleanup, cheat sheets |
| **Day 9** | Networking Deep Dive (ip/ss, DNS, tcpdump, UFW, netns) | [Materials_9](Day9/day9_en.md) |
| **Day 10** | Networking (Part 2): NAT / DNAT / netns / UFW Deep | [Materials_10](Day10/day10_en.md) |
| **Day 11** | Networking (Part 3): nftables NAT/DNAT + Persistence | [Materials_11](Day11/day11_en.md) |
---

## How to use
- Each day: **Goals → Practice → Mini-lab → Summary** in `dayN_en.md`.
- Labs under `labs/dayN/…`, scripts under `tools/`.
- If copied from `/etc` or `/usr/local/bin` with sudo, fix ownership before commit:
  ```bash
  sudo chown -R "$(id -un)":"$(id -gn)" labs tools
  ```
- Make scripts executable:
  ```bash
  chmod +x tools/*.sh
  ```
---

## Example — Day 5 quick check
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
