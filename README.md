# 📌 DevOps Learning Journey / Путь обучения DevOps

**RU:** Мой путь в DevOps с нуля до первой работы — ежедневные конспекты, практики и мини‑проекты.  
**EN:** My journey in DevOps from scratch to first job — daily notes, labs, and mini‑projects.

---

## 📂 Repository structure
```
devops-notes/
 ├─ Day1/
 │   ─ day1_en.md
 ├─ Day2/
 │   └─ day2_en.md
 ├─ Day3/
 │   └─ day3_en.md
 ├─ Prep_Evening/
 │   └─ Prep_Evening1.pdf
 ├─ Day4/
 │   └─ Day4_Materials_EN.md
 ├─ Day5/
 │   └─ Day5_Materials_EN.md
 ├─ Day6/
 │   └─ Day6_Materials_EN.md
 ├─ Day7/
 │   └─ day7_en.md
 ├─ labs/
 │   └─ day4/
 |      └─ SGID_ACL%20_v1.md
 │   └─ day5/
 |      ├─ flaky.service
 |      ├─ hello.service
 |      ├─ hello.timer
 |      └─ persistent.conf
 ├─ tools/
 |    ├─ apt-dry-upgrade.sh
 |    ├─ hello.sh
 |    ├─ pkg-restore.sh
 |    ├─ pkg-snapshot.sh
 |    ├─ backup-dir.sh
 |    ├─ backup-dir.v2.sh
 |    ├─ devops-tail.sh
 |    ├─ devops-tail.v2.sh
 |    ├─ rename-ext.sh
 |    ├─ rename-ext.v2.sh
 |    ├─ _template.sh
 │    └─ mkshare.sh
 ├─ DevOps_Progress.md
 └─ README.md
```

> Если каких‑то файлов ещё нет — добавлю их позже. / If some files are missing yet — they’ll be added later.

---

## 📅 Calendar
| Day | Topic | Materials |
|-----|-------|-----------|
| **Day 1** | Environment Setup and Basic Linux Commands | [Materials_1](Day1/day1_en.md) |
| **Day 2** | Nano basics; file ops; permissions; mini-lab project folder | [Materials_2](Day2/day2_en.md) |
| **Day 3** | Networking basics; network tools; network diagnostics lab | [Materials_3](Day3/day3_en.md) |
| **Day !** | Prep evening: revision Day1–3; extra practice | [Materials_EV](Prep_Evening/Prep_Evening1.pdf) |
| **Day 4** | Users & Groups; shared dirs with SGID + default ACL; account policies (chage); sudoers (safe cmds); 2 mini-labs; mkshare_v1 | [Materials_4](Day4/Day4_Materials_EN.md) | 
| **Day 5** | Processes & Services — systemd basics; journalctl; custom service+timer; restart policy; transient unit | [Materials_5](Day5/Day5_Materials_EN.md) |
| **Day 6** | APT/dpkg — search/show/policy; versions; files & owners; holds; snapshot/restore (dry); unattended-upgrades (dry-run) | [Materials_6](Day6/Day6_Materials_EN.md) |
| **Day 7** | Bash Scripting (template, rename, backup, logs) | [Materials_7](Day7/day7_en.md) |
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
**EN:** Learn Linux, networking, scripting, CI/CD, containers, cloud, and automation to get a DevOps engineer job.  
