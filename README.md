# 📌 DevOps Learning Journey / Путь обучения DevOps

**RU:** Мой путь в DevOps с нуля до первой работы — ежедневные конспекты, практики и мини‑проекты.  
**EN:** My journey in DevOps from scratch to first job — daily notes, labs, and mini‑projects.

---

## 📂 Repository structure
```
devops-notes/
 ├─ Day1/
 │   ├─ Day1_Materials_EN.pdf
 │   ├─ Day1_Materials_RU.pdf
 │   ├─ Day1_Schedule_EN.pdf
 │   └─ Day1_Schedule_RU.pdf
 ├─ Day2/
 │   ├─ Day2_Project_Folder_Setup_Script_EN.pdf
 │   ├─ Day2_Project_Folder_Setup_Script_RU.pdf
 │   ├─ Day2_Materials_EN.pdf
 │   ├─ Day2_Materials_RU.pdf
 │   ├─ Day2_Schedule_EN.pdf
 │   └─ Day2_Schedule_RU.pdf
 ├─ Day3/
 │   ├─ Day3_Network_Diagnostics_Lab_EN.pdf
 │   ├─ Day3_Materials_EN.pdf
 │   └─ Day3_Schedule_EN.pdf
 ├─ Prep_Evening/
 │   ├─ Prep_Evening1.pdf
 │   └─ Prep_Evening_Schedule1.pdf
 ├─ Day4/
 │   ├─ Day4_Materials_EN.md
 │   └─ Day4_Schedule_EN.md
 ├─ Day5/
 │   ├─ Day5_Materials_EN.md
 │   └─ Day5_Schedule_EN.md
 ├─ Day6/
 │   ├─ Day6_Materials_EN.md
 │   └─ Day6_Schedule_EN.md
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
 │    └─ mkshare.sh
 ├─ DevOps_Progress.md
 └─ README.md
```

> Если каких‑то файлов ещё нет — добавлю их позже. / If some files are missing yet — they’ll be added later.

---

## 📅 Calendar / Календарь
| Day | Topic | Materials | Schedule |
|-----|-------|-----------|----------|
| **Day 1** | Environment Setup and Basic Linux Commands | [Materials_1](Day1/Day1_Materials_EN.pdf) | [Schedule_1](Day1/Day1_Schedule_EN.pdf) |
| **Day 2** | Nano basics; file ops; permissions; mini-lab project folder | [Materials_2](Day2/Day2_Materials_EN.pdf) | [Schedule_2](Day2/Day2_Schedule_EN.pdf) |
| **Day 3** | Networking basics; network tools; network diagnostics lab | [Materials_3](Day3/Day3_Materials_EN.pdf) |[Schedule_3](Day3/Day3_Schedule_EN.pdf) |
| **Day !** | Prep evening: revision Day1–3; extra practice | [Materials_EV](Prep_Evening/Prep_Evening1.pdf) | [Schedule_EV](Prep_Evening/Prep_Evening_Schedule1.pdf) |
| **Day 4** | Users & Groups; shared dirs with SGID + default ACL; account policies (chage); sudoers (safe cmds); 2 mini-labs; mkshare_v1 | [Materials_4](Day4/Day4_Materials_EN.md) | [Schedule_4](Day4/Day4_Schedule_EN.md) |
| **Day 5** | Processes & Services — systemd basics; journalctl; custom service+timer; restart policy; transient unit | [Materials_5](Day5/Day5_Materials_EN.md) | [Schedule_5](Day5/Day5_Schedule_EN.md) |
| **Day 6** | APT/dpkg — search/show/policy; versions; files & owners; holds; snapshot/restore (dry); unattended-upgrades (dry-run) | [Materials_6](Day6/Day6_Materials_EN.md) | [Schedule_6](Day6/Day6_Schedule_EN.md) |
---

## 🧪 Mini‑labs
- **Project Folder Setup Script** — [PDF](Day2/Day2_Project_Folder_Setup_Script_EN.pdf) |
- **Network Diagnostics Lab** — [PDF](Day3/Day3_Network_Diagnostics_Lab_EN.pdf) |
- **Automation: mkshare (v1)** — [MD](labs/day4/SGID_ACL%20_v1.md) |
---

## How to use
- Each day: **Goals → Practice → Mini-lab → Summary** in `DayN_EN.md`.
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

## 📈 Progress / Прогресс
- Daily log / Журнал прогресса: [DevOps_Progress.md](DevOps_Progress.md)

---

## 🎯 Goal / Цель
**EN:** Learn Linux, networking, scripting, CI/CD, containers, cloud, and automation to get a DevOps engineer job.  
**RU:** Освоить Linux, сети, скрипты, CI/CD, контейнеры, облака и автоматизацию, чтобы устроиться DevOps‑инженером.
