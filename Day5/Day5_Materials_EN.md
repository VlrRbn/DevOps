# Day5_Materials_EN

---

# Processes & Services

**Date:** 25.08.2025

**Start time:** 16:00

**Total duration:** ~6h 

---

## Goals

- Understand processes & `systemd` basics.
- Create a custom `systemd` **service + timer**.
- Read and filter logs with `journalctl`.

---

## Theory quick notes

- `ps aux`, `pstree`, signals (`SIGTERM` vs `SIGKILL`).
- `systemd`: units (service, timer), `systemctl` lifecycle.
- `journald`: filters `-u` (*unit*), `-p` (priority), `-b`(boot), `-f`(follow), `-t` (identifier tag).

---

## Practice

- Inspect `cron`: `systemctl status/cat/show`, drop-in override (Environment=HELLO=world).
- Build `hello.service` (oneshot) + `hello.timer` (every 5 min).
- Verify: `list-timers`, `journalctl -u hello.service` and `t hello`.

## Mini-lab

- Build `/usr/local/bin/hello.sh` + units in `/etc/systemd/system/`.
- Enable timer, verify with `list-timers` and logs.
- `flaky.service` with `Restart=on-failure`.
- Basic hardening: `ProtectSystem=strict`, `PrivateTmp`, `NoNewPrivileges`.
- Transient unit: `systemd-run --unit=now-echo ...`.

---

## Quick mini-lab “Processes”

1) Who eats CPU/memory.

`ps aux --sort=-%cpu | head`

```bash
leprecha@Ubuntu-DevOps:~$ ps aux --sort=-%cpu | head -2
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
leprecha   16533 31.8  3.2 1478621296 525316 ?   Sl   21:51   0:30 /opt/google/chrome/chrome --type=renderer --crashpad-handler-pid=14706 --enable-crash-reporter=557550b2-f1f6-4d05-90cc-1deae0f5f3fa, --change-stack-guard-on-fork=enable --ozone-platform=x11 --lang=en-US --num-raster-threads=4 --enable-main-frame-before-activation --renderer-client-id=43 --time-ticks-at-unix-epoch=-1756133990575695 --launch-time-ticks=21101841303 --shared-files=v8_context_snapshot_data:100 --metrics-shmem-handle=4,i,8753477971298591934,7052031657596811397,2097152 --field-trial-handle=3,i,24681192782921135,9795654689833914453,262144 --variations-seed-version=20250825-050038.168000
```

`ps aux --sort=-%mem | head`

```bash
leprecha@Ubuntu-DevOps:~$ ps aux --sort=-%mem | head -2
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
leprecha   15083 15.7  4.9 1482060916 787784 ?   Sl   20:44  10:59 /opt/google/chrome/chrome --type=renderer --crashpad-handler-pid=14706 --enable-crash-reporter=557550b2-f1f6-4d05-90cc-1deae0f5f3fa, --change-stack-guard-on-fork=enable --ozone-platform=x11 --lang=en-US --num-raster-threads=4 --enable-main-frame-before-activation --renderer-client-id=20 --time-ticks-at-unix-epoch=-1756133990575695 --launch-time-ticks=17078237958 --shared-files=v8_context_snapshot_data:100 --metrics-shmem-handle=4,i,8951425184311289951,3324895699145417550,2097152 --field-trial-handle=3,i,24681192782921135,9795654689833914453,262144 --variations-seed-version=20250825-050038.168000

```

Lists processes, sorted by CPU or memory usage.

Purpose: spot resource hogs quickly.

---

2) Process tree — `pstree -p`.

```bash
leprecha@Ubuntu-DevOps:~$ pstree -p | head -20
systemd(1)-+-ModemManager(1405)-+-{ModemManager}(1439)
           |                    |-{ModemManager}(1442)
           |                    `-{ModemManager}(1446)
           |-NetworkManager(1335)-+-{NetworkManager}(1415)
           |                      |-{NetworkManager}(1419)
           |                      `-{NetworkManager}(1420)
           |-accounts-daemon(1224)-+-{accounts-daemon}(1278)
           |                       |-{accounts-daemon}(1279)
           |                       `-{accounts-daemon}(1337)
           |-avahi-daemon(1186)---avahi-daemon(1254)
           |-bluetoothd(1187)
           |-boltd(1410)-+-{boltd}(1426)
           |             |-{boltd}(1428)
           |             `-{boltd}(1430)
           |-colord(1937)-+-{colord}(1951)
           |              |-{colord}(1952)
           |              `-{colord}(1954)
           |-cron(11048)
           |-cups-browsed(2258)-+-{cups-browsed}(2266)
           |                    |-{cups-browsed}(2267)
```

Purpose: visualize parent-child relations (PPID → PID).

---

3) Test subject.

```bash
leprecha@Ubuntu-DevOps:~$ sleep 300 & # start "sleep" in the background for 5 minutes
[1] 16706
leprecha@Ubuntu-DevOps:~$ S=$! # store the PID of the last background process in variable $S
leprecha@Ubuntu-DevOps:~$ ps -p "$S" -o pid,ppid,stat,etime,cmd
    PID    PPID STAT     ELAPSED CMD
  16706   16090 S          00:11 sleep 300
leprecha@Ubuntu-DevOps:~$ pstree -p | grep -m1 "sleep($S)" || true
           |               |                        |             `-sleep(16706)
```

This `ps` command shows detailed info about the process:

- **pid** — the process ID itself;
- **ppid** — the parent process ID;
- **stat** — the current state (`S` = sleeping, `R` = running, `Z` = zombie.);
- **etime** — how long the process has been running;
- **cmd** — the command that started it;
- `pstree -p` builds a tree of processes including PIDs;
- `grep -m1 "sleep($S)"` looks for the first line that matches `sleep` with that PID;
- `|| true` ensures the script won’t fail if `grep` doesn’t find anything (e.g. if the process has already exited).

Purpose: practice finding and inspecting a specific PID.

---

4) Signals: gentle → hard.

```bash
kill -SIGTERM "$S"     # ask the process to exit (default signal 15)
sleep 1                # wait a moment
ps -p "$S" -o pid,stat || echo "terminated"
```

- `SIGTERM` = The process can **catch it, clean up, and exit gracefully**.
- `sleep 1` = give it a second to actually exit.
- `ps ... || echo "terminated"` = check if it’s still alive. If not found, print `terminated`.

Rule of thumb in Linux admin / DevOps:

1. Always try `SIGTERM` first (graceful).
2. Only use `SIGKILL` if the process ignores termination (zombie or stuck).

---

# **systemd + journalctl**

### Warm-up.

Goal: understand what’s actually running right now.

`hostnamectl` — is a **systemd** utility that:

```bash
leprecha@Ubuntu-DevOps:~$ hostnamectl
 Static hostname: Ubuntu-DevOps
       Icon name: computer-laptop
         Chassis: laptop 💻
      Machine ID: <redacted>
         Boot ID: <redacted>
Operating System: Ubuntu 24.04.3 LTS                   
          Kernel: Linux 6.14.0-28-generic
    Architecture: x86-64
 Hardware Vendor: ASUSTeK COMPUTER INC.
  Hardware Model: ASUS TUF Gaming F15 FX507ZC4_FX507ZC4
Firmware Version: FX507ZC4.312
   Firmware Date: Tue 2024-12-03
    Firmware Age: 8month 3w 1d
```

### Displays system information — shows:

- hostname (static, transient, pretty);
- OS and version;
- kernel;
- architecture;
- hardware vendor & model;
- firmware version.

---

**Changes the hostname.**

- `sudo hostnamectl set-hostname myserver` — sets a new hostname.
- Supports three types:
    - **static** — permanent, stored in `/etc/hostname`;
    - **transient** — temporary (until reboot);
    - **pretty** — “fancy” name, with spaces/emojis.

---

`systemctl list-units --type=service --state=running | head -5`

What it does:

1. **`systemctl list-units`** — shows all units managed by systemd.
2. **`--type=service`** — filters only services.
3. **`--state=running`** — shows only those currently running.
4. **`| head -20`** — limits the output to the first 20 lines (otherwise the list can be very long).

```bash
leprecha@Ubuntu-DevOps:~$ systemctl list-units --type=service --state=running | head -5
  UNIT                                    LOAD   ACTIVE SUB     DESCRIPTION
  accounts-daemon.service                 loaded active running Accounts Service
  avahi-daemon.service                    loaded active running Avahi mDNS/DNS-SD Stack
  bluetooth.service                       loaded active running Bluetooth service
  bolt.service                            loaded active running Thunderbolt system service
```

---

`systemctl is-system-running` - checks the overall system status as seen by **systemd**.

- Returns a single word:

Possible states:

- `running` — everything is working normally.
- `degraded` — system is up, but some units failed.
- `starting` — system is still booting.
- `stopping` — system is shutting down.
- `maintenance` (or `rescue`) — system in recovery mode.
- `offline` — systemd is not available.
- `unknown` — unknown state 😅

---

### Anatomy of a unit using cron as an example

Goal: to see what a service consists of.

`systemctl status cron` — displays the detailed status of the **cron** service (the job scheduler).

- It will show:
    - whether the service is active (`active (running)` / `inactive` / `failed`);
    - PID and uptime;
    - binary path;
    - recent logs (usually last 10 lines from `journalctl`).

```bash
leprecha@Ubuntu-DevOps:~$ systemctl status cron
● cron.service - Regular background program processing daemon
     Loaded: loaded (/usr/lib/systemd/system/cron.service; enabled; preset: ena>
     Active: active (running) since Mon 2025-08-25 16:12:44 IST; 19min ago
       Docs: man:cron(8)
   Main PID: 7364 (cron)
      Tasks: 1 (limit: 18465)
     Memory: 368.0K (peak: 2.4M)
        CPU: 53ms
     CGroup: /system.slice/cron.service
             └─7364 /usr/sbin/cron -f -P

Aug 25 16:15:01 Ubuntu-DevOps CRON[7381]: pam_unix(cron:session): session close>
Aug 25 16:17:01 Ubuntu-DevOps CRON[7499]: pam_unix(cron:session): session opene>
Aug 25 16:17:01 Ubuntu-DevOps CRON[7500]: (root) CMD (cd / && run-parts --repor>
Aug 25 16:17:01 Ubuntu-DevOps CRON[7499]: pam_unix(cron:session): session close>
Aug 25 16:25:01 Ubuntu-DevOps CRON[7547]: pam_unix(cron:session): session opene>
Aug 25 16:25:01 Ubuntu-DevOps CRON[7548]: (root) CMD (command -v debian-sa1 > />
Aug 25 16:25:01 Ubuntu-DevOps CRON[7547]: pam_unix(cron:session): session close>
Aug 25 16:30:01 Ubuntu-DevOps CRON[7641]: pam_unix(cron:session): session opene>
Aug 25 16:30:01 Ubuntu-DevOps CRON[7642]: (root) CMD ([ -x /etc/init.d/anacron >
Aug 25 16:30:01 Ubuntu-DevOps CRON[7641]: pam_unix(cron:session): session close>
```

---

`systemctl cat cron` — displays the **unit file** of the `cron` service (as systemd sees it).

```bash
leprecha@Ubuntu-DevOps:~$ systemctl cat cron
# /usr/lib/systemd/system/cron.service
[Unit]
Description=Regular background program processing daemon
Documentation=man:cron(8)
After=remote-fs.target nss-user-lookup.target

[Service]
EnvironmentFile=-/etc/default/cron
ExecStart=/usr/sbin/cron -f -P $EXTRA_OPTS
IgnoreSIGPIPE=false
KillMode=process
Restart=on-failure
SyslogFacility=cron

[Install]
WantedBy=multi-user.target
```

Useful to check:

- which binary is launched (`ExecStart`);
- what options are applied;
- where the unit file is located;
- if there are **drop-in overrides** (`/etc/systemd/system/cron.service.d/*.conf`).

---

`systemctl show -p FragmentPath,UnitFileState,ActiveState,SubState,MainPID,ExecStart,Restart,RestartUSec cron` - It prints only selected properties of the `cron` unit:

```bash
leprecha@Ubuntu-DevOps:~$ systemctl show -p FragmentPath,UnitFileState,ActiveState,SubState,MainPID,ExecStart,Restart,RestartUSec cron
Restart=on-failure
RestartUSec=100ms
MainPID=7364
ExecStart={ path=/usr/sbin/cron ; argv[]=/usr/sbin/cron -f -P $EXTRA_OPTS ; ign>
ActiveState=active
SubState=running
FragmentPath=/usr/lib/systemd/system/cron.service
UnitFileState=enabled
```

- **FragmentPath** — path to the unit file (e.g. `/usr/lib/systemd/system/cron.service`).
- **UnitFileState** — state of the unit file.
- **ActiveState** — high-level state: `active`, `inactive`, `failed` .
- **SubState** — more detailed state.
- **MainPID** — PID of the main process.
- **ExecStart** — command used to start it.
- **Restart** — restart policy (e.g. `on-failure`).
- **RestartUSec** — restart delay.

---

### Logs with journalctl

Goal: filter by unit, time, and priority level.

`journalctl` — is the tool to read the **systemd journal logs**.

`cron` — logs into the journal (syslog facility `cron`), we can inspect its activity with `journalctl`.

`journalctl -u cron` — show all logs for the **cron** service (from the beginning of the journal).

`journalctl -u cron -o json-pretty -n 3` — output last 3 entries in JSON format, nicely formatted. For debugging, has **extra metadata** not shown in plain output (`_PID`, `_UID`, `_COMM`, `_HOSTNAME`).

```bash
leprecha@Ubuntu-DevOps:~$ journalctl -u cron --since "15 min ago" --no-pager | tail -n 10
Aug 25 16:45:01 Ubuntu-DevOps CRON[7737]: pam_unix(cron:session): session opened for user root(uid=0) by root(uid=0)
Aug 25 16:45:01 Ubuntu-DevOps CRON[7737]: pam_unix(cron:session): session closed for user root
Aug 25 16:55:01 Ubuntu-DevOps CRON[7916]: pam_unix(cron:session): session opened for user root(uid=0) by root(uid=0)
Aug 25 16:55:01 Ubuntu-DevOps CRON[7916]: pam_unix(cron:session): session closed for user root
```

---

`journalctl -fu cron` — follow cron logs in real time (like `tail -f`). Stop with `Ctrl+C`.

```bash
leprecha@Ubuntu-DevOps:~$ journalctl -fu cron
Aug 25 16:55:01 Ubuntu-DevOps CRON[7916]: pam_unix(cron:session): session opened for user root(uid=0) by root(uid=0)
Aug 25 16:55:01 Ubuntu-DevOps CRON[7916]: pam_unix(cron:session): session closed for user root
```

---

`journalctl -p warning..alert -n 10 --no-pager` — show the last 10 log entries with **priority warning and higher** (warning, err, crit, alert, emerg). No pager.

```bash
leprecha@Ubuntu-DevOps:~$ journalctl -p warning..alert -n 1 --no-pager
Aug 25 16:57:43 Ubuntu-DevOps /usr/libexec/gdm-x-session[4910]: See https://wayland.freedesktop.org/libinput/doc/1.25.0/touchpad-jumping-cursors.html for details
```

---

`journalctl -b -u cron -n 5 --no-pager` — show the last 5 cron log entries for the **current system boot only**.

```bash
leprecha@Ubuntu-DevOps:~$ journalctl -b -u cron -n 5 --no-pager
Aug 25 16:55:01 Ubuntu-DevOps CRON[7916]: pam_unix(cron:session): session opened for user root(uid=0) by root(uid=0)
Aug 25 16:55:01 Ubuntu-DevOps CRON[7916]: pam_unix(cron:session): session closed for user root
Aug 25 17:00:01 Ubuntu-DevOps CRON[7943]: pam_unix(cron:session): session opened for user root(uid=0) by root(uid=0)
Aug 25 17:00:01 Ubuntu-DevOps CRON[7944]: (root) CMD (timeshift --check --scripted)
Aug 25 17:00:01 Ubuntu-DevOps CRON[7943]: pam_unix(cron:session): session closed for user root
```

---

`journalctl --disk-usage` — check how much disk space the systemd journal uses.

```bash
leprecha@Ubuntu-DevOps:~$ journalctl --disk-usage
Archived and active journals take up 311.4M in the file system.
```

---

`sudo systemctl restart cron` — restarts the **cron** service, then `journalctl -u cron -n 10 --no-pager`.

```bash
leprecha@Ubuntu-DevOps:~$ sudo systemctl restart cron
leprecha@Ubuntu-DevOps:~$ journalctl -u cron -n 10 --no-pager
Aug 25 17:00:01 Ubuntu-DevOps CRON[7943]: pam_unix(cron:session): session opened for user root(uid=0) by root(uid=0)
Aug 25 17:00:01 Ubuntu-DevOps CRON[7944]: (root) CMD (timeshift --check --scripted)
Aug 25 17:00:01 Ubuntu-DevOps CRON[7943]: pam_unix(cron:session): session closed for user root
Aug 25 17:04:55 Ubuntu-DevOps systemd[1]: Stopping cron.service - Regular background program processing daemon...
Aug 25 17:04:55 Ubuntu-DevOps systemd[1]: cron.service: Deactivated successfully.
Aug 25 17:04:55 Ubuntu-DevOps systemd[1]: Stopped cron.service - Regular background program processing daemon.
Aug 25 17:04:55 Ubuntu-DevOps (cron)[8049]: cron.service: Referenced but unset environment variable evaluates to an empty string: EXTRA_OPTS
Aug 25 17:04:55 Ubuntu-DevOps systemd[1]: Started cron.service - Regular background program processing daemon.
Aug 25 17:04:55 Ubuntu-DevOps cron[8049]: (CRON) INFO (pidfile fd = 3)
Aug 25 17:04:55 Ubuntu-DevOps cron[8049]: (CRON) INFO (Skipping @reboot jobs -- not system startup)
```

---

### Drop-in override (safe service editing)

Goal: avoid editing the original unit by applying an “overlay.”

`sudo systemctl edit cron` — command **creates or opens an override configuration** for the `cron.service` unit.

- It does **not** modify the original file `/usr/lib/systemd/system/cron.service`.
- Instead, it creates a drop-in file.
- The drop-in lives under `/etc/systemd/system/cron.service.d/override.conf`.

---

1. Created a directory for overrides: `mkdir -p /etc/systemd/system/cron.service.d` .
2. Wrote an `override.conf`: with `Environment=HELLO=world` .
3. Reloaded systemd configs: `systemctl daemon-reload` .
4. Restarted the service: `systemctl restart cron` (PID changed after restart).
5. Verified with: `systemctl cat cron` .
6. And got: `Environment=HELLO=world` .

```bash
leprecha@Ubuntu-DevOps:~$ sudo mkdir -p /etc/systemd/system/cron.service.d
leprecha@Ubuntu-DevOps:~$ printf "[Service]\nEnvironment=HELLO=world\n" | sudo tee /etc/systemd/system/cron.service.d/override.conf >/dev/null
leprecha@Ubuntu-DevOps:~$ sudo systemctl daemon-reload
leprecha@Ubuntu-DevOps:~$ sudo systemctl restart cron
leprecha@Ubuntu-DevOps:~$ systemctl cat cron
# /usr/lib/systemd/system/cron.service
[Unit]
Description=Regular background program processing daemon
Documentation=man:cron(8)
After=remote-fs.target nss-user-lookup.target

[Service]
EnvironmentFile=-/etc/default/cron
ExecStart=/usr/sbin/cron -f -P $EXTRA_OPTS
IgnoreSIGPIPE=false
KillMode=process
Restart=on-failure
SyslogFacility=cron

[Install]
WantedBy=multi-user.target

# /etc/systemd/system/cron.service.d/override.conf
[Service]
Environment=HELLO=world
```

---

### Signals and interaction.

`systemctl status cron | sed -n '1,12p'` - shows `systemctl status` but **only the first 12 lines** via `sed`.

**`sed`** — *stream editor*.

It processes text line by line (from a file or stdin) and can:

- extract lines,
- substitute text,
- insert/delete lines,
- act as a filter in a pipeline.

```bash
leprecha@Ubuntu-DevOps:~$ systemctl status cron | sed -n '1,12p'
● cron.service - Regular background program processing daemon
     Loaded: loaded (/usr/lib/systemd/system/cron.service; enabled; preset: enabled)
    Drop-In: /etc/systemd/system/cron.service.d
             └─override.conf
     Active: active (running) since Mon 2025-08-25 17:35:01 IST; 18min ago
       Docs: man:cron(8)
   Main PID: 10549 (cron)
      Tasks: 1 (limit: 18465)
     Memory: 348.0K (peak: 2.3M)
        CPU: 16ms
     CGroup: /system.slice/cron.service
             └─10549 /usr/sbin/cron -f -P
```

---

`systemctl show -p MainPID cron` — shows PID.

`ps -fp "$(systemctl show -p MainPID --value cron)"`.

- `systemctl show -p MainPID --value cron` → extracts the **main PID**.
- `ps -fp <PID>` → prints a **human-friendly** process line (UID, PID, …, CMD).
- Confirms **which binary** is running and its **arguments**.

```bash
leprecha@Ubuntu-DevOps:~$ systemctl show -p MainPID cron
MainPID=10549
leprecha@Ubuntu-DevOps:~$ ps -fp "$(systemctl show -p MainPID --value cron)"
UID          PID    PPID  C STIME TTY          TIME CMD
root       10549       1  0 17:35 ?        00:00:00 /usr/sbin/cron -f -P
```

---

### System status and timers

`systemctl list-timers --all | head -5` — lists all systemd timers (active/inactive) with next/last run. `head -5` trims to first 5 lines.

**When to use:**

- Audit **scheduled jobs** (systemd timers instead of cron).
- Debug **missed or mistimed** runs.
- See which **service a timer activates** (`UNIT`/`ACTIVATES` columns).

```bash
leprecha@Ubuntu-DevOps:~$ systemctl list-timers --all | head -5
NEXT                            LEFT LAST                              PASSED UNIT                           ACTIVATES
Mon 2025-08-25 18:20:00 IST     8min Mon 2025-08-25 18:10:03 IST 1min 11s ago sysstat-collect.timer          sysstat-collect.service
Mon 2025-08-25 18:28:50 IST    17min Mon 2025-08-25 17:25:17 IST    45min ago fwupd-refresh.timer            fwupd-refresh.service
Mon 2025-08-25 18:34:33 IST    23min Mon 2025-08-25 17:31:12 IST    40min ago anacron.timer                  anacron.service
Mon 2025-08-25 20:27:21 IST 2h 16min Tue 2025-08-19 15:19:24 IST            - update-notifier-motd.timer     update-notifier-motd.service

```

---

`systemctl --failed` — shows **failed** units.

**When to use:**

- Quick **health check** after boot or config changes.
- Starting point for debugging: then `systemctl status <unit>` and `journalctl -u <unit>`.

```bash
leprecha@Ubuntu-DevOps:~$ systemctl --failed
  UNIT LOAD ACTIVE SUB DESCRIPTION

0 loaded units listed.
```

---

`systemd-analyze blame | head -15` — ranks units by init time on **last boot**; `head -15` shows the slowest offenders.

**When to use:**

- **Boot time** tuning: find slow services.
- Decide what to **delay**, disable, or rework.

```bash
leprecha@Ubuntu-DevOps:~$ systemd-analyze blame | head -15
22.751s fstrim.service
 6.044s plymouth-quit-wait.service
 5.794s NetworkManager-wait-online.service
 4.009s apt-daily.service
 2.645s nvidia-suspend.service
 2.573s systemd-suspend.service
 2.143s snapd.seeded.service
 2.059s snapd.service
 1.545s plymouth-read-write.service
 1.042s systemd-backlight@backlight:intel_backlight.service
  998ms fwupd.service
  880ms NetworkManager.service
  730ms thermald.service
  396ms apport.service
  298ms dev-nvme0n1p2.device
```

### Handy extras

- Timer → service:
    
    ```bash
    systemctl cat <timer>.timer
    systemctl status <timer>.timer
    ```
    

---

- Boot breakdown:

`systemd-analyze time` — shows **how fast the system booted** on the last startup:

- total boot time,
- firmware/bootloader,
- kernel,
- user space (systemd + services).
    
    ```bash
    leprecha@Ubuntu-DevOps:~$ systemd-analyze time
    Startup finished in 6.095s (firmware) + 2.190s (loader) + 7.880s (kernel) + 10.348s (userspace) = 26.516s 
    graphical.target reached after 10.312s in userspace.
    
    systemd-analyze critical-chain
    ```
    

---

`systemd-analyze critical-chain` — displays the **critical chain of units** that formed the boot path.

- Units are shown in dependency order.
- Shows how long each took to start or how long it delayed others.

```bash
leprecha@Ubuntu-DevOps:~$ systemd-analyze critical-chain
The time when unit became active or started is printed after the "@" character.
The time the unit took to start is printed after the "+" character.

graphical.target @10.312s
└─multi-user.target @10.311s
  └─plymouth-quit-wait.service @4.265s +6.044s
    └─systemd-user-sessions.service @4.245s +15ms
      └─network.target @4.225s
        └─NetworkManager.service @3.345s +880ms
          └─dbus.service @3.204s +138ms
            └─basic.target @3.199s
              └─sockets.target @3.199s
                └─snapd.socket @3.139s +59ms
                  └─sysinit.target @3.137s
                    └─plymouth-read-write.service @1.591s +1.545s
                      └─local-fs.target @1.588s
                        └─run-snapd-ns-snapd\x2ddesktop\x2dintegration.mnt.mount @5.641s
                          └─run-snapd-ns.mount @5.128s
                            └─local-fs-pre.target @442ms
                              └─systemd-tmpfiles-setup-dev.service @434ms +7ms
                                └─systemd-tmpfiles-setup-dev-early.service @410ms +14ms
                                  └─kmod-static-nodes.service @400ms +7ms
                                    └─systemd-journald.socket @390ms
                                      └─-.mount @345ms
                                        └─-.slice @345ms
```

---

`systemctl list-dependencies cron` — lists the **dependency tree** for the `cron.service`.

- Shows:
    - which units `cron` pulls in,
    - what it depends on,
    - the targets it’s tied to (e.g., `multi-user.target`).
    

When it’s useful

- **Debugging**: if the service won’t start (maybe a dependency failed).
- **Understanding the boot graph**: which targets ensure cron is up.
- **Boot optimization**: trim/move dependencies to delay or speed up start.
- **Strict ordering**: e.g., ensure `cron` only starts after NFS is mounted.

---

## Mini-lab: your own service + timer (logger every 5 minutes)

1. **Script.**

```bash
leprecha@Ubuntu-DevOps:~$ sudo tee /usr/local/bin/hello.sh >/dev/null <<'SH'
> #!/usr/bin/env bash
> echo "[hello] $(date '+%F %T') $(hostname)" | systemd-cat -t hello -p info
> SH

leprecha@Ubuntu-DevOps:~$ sudo chmod +x /usr/local/bin/hello.sh
```

### What it does:

1. **`sudo tee /usr/local/bin/hello.sh`**
    - Creates the file `hello.sh` in `/usr/local/bin/` as root.
    - `tee` writes the script content into it.
    - `>/dev/null` suppresses the echo to the terminal.
2. **`#!/usr/bin/env bash`**
    - Shebang: run with `bash`.
3. **`echo "[hello] …" | systemd-cat -t hello -p info`**
    - Generates a log line with date, time, and hostname.
    - `systemd-cat` sends it to the **systemd journal**.
    - `-t hello` → log tag = `hello`.
    - `-p info` → log priority = info.

---

2. Service unit.

```bash
leprecha@Ubuntu-DevOps:~$ sudo tee /etc/systemd/system/hello.service >/dev/null <<'UNIT'
> [Unit]
> Description=Hello logger (oneshot)
> 
> [Service]
> Type=oneshot
> ExecStart=/usr/local/bin/hello.sh
> UNIT
```

### Meaning:

- **[Unit]**
    - `Description=Hello logger (oneshot)` → description shown in `systemctl status`.
- **[Service]**
    - `Type=oneshot` → runs once, executes the command, then exits.
    - `ExecStart=/usr/local/bin/hello.sh` → script to run.
    
    ---
    
    3. Timer.
    

```bash
leprecha@Ubuntu-DevOps:~$ sudo tee /etc/systemd/system/hello.timer >/dev/null << 'UNIT'
> [Unit]
> Description=Run hello.service every 5 minutes
> 
> [Timer]
> OnBootSec=1min
> OnUnitActiveSec=5min
> Unit=hello.service
> 
> [Install]
> WantedBy=timers.target
> UNIT
```

### Meaning:

- **[Unit]**
    - Description shows up in `systemctl list-timers`.
- **[Timer]**
    - `OnBootSec=1min` → first run happens 1 minute after boot.
    - `OnUnitActiveSec=5min` → repeat every 5 minutes after last successful run.
    - `Unit=hello.service` → service to trigger.
- **[Install]**
    - `WantedBy=timers.target` → included with other timers.

---

4. Start and check.

1. Reloads all unit files so systemd picks up the new timer.
2. Runs the `hello.service` manually. In `journalctl`.
3. Checks if your timer is scheduled. 
4. Shows the last 20 logs from the `hello.service` in the past 10 minutes.

Enables the **timer** permanently and starts it immediately.

- First run happens 1 minute after boot (`OnBootSec=1min`).
- Then every 5 minutes (`OnUnitActiveSec=5min`).

```bash
leprecha@Ubuntu-DevOps:~$ sudo systemctl daemon-reload
leprecha@Ubuntu-DevOps:~$ sudo systemctl start hello.service
leprecha@Ubuntu-DevOps:~$ sudo systemctl enable --now hello.timer
leprecha@Ubuntu-DevOps:~$ systemctl list-timers --all | grep hello || systemctl list-timers --all | head -5
Mon 2025-08-25 19:48:09 IST 4min 44s Mon 2025-08-25 19:41:20 IST  2min 4s ago hello.timer                    hello.service
leprecha@Ubuntu-DevOps:~$ journalctl -u hello.service --since "10 min ago" -n 20 --no-pager
Aug 25 19:36:18 Ubuntu-DevOps systemd[1]: Starting hello.service - Hello logger (oneshot)...
Aug 25 19:36:18 Ubuntu-DevOps systemd[1]: hello.service: Deactivated successfully.
Aug 25 19:36:18 Ubuntu-DevOps systemd[1]: Finished hello.service - Hello logger (oneshot).
Aug 25 19:41:20 Ubuntu-DevOps systemd[1]: Starting hello.service - Hello logger (oneshot)...
Aug 25 19:41:20 Ubuntu-DevOps systemd[1]: hello.service: Deactivated successfully.
Aug 25 19:41:20 Ubuntu-DevOps systemd[1]: Finished hello.service - Hello logger (oneshot).
Aug 25 19:43:09 Ubuntu-DevOps systemd[1]: Starting hello.service - Hello logger (oneshot)...
Aug 25 19:43:09 Ubuntu-DevOps systemd[1]: hello.service: Deactivated successfully.
Aug 25 19:43:09 Ubuntu-DevOps systemd[1]: Finished hello.service - Hello logger (oneshot).
```

### What is `grep` hello

- `grep` — search tool for text.
- It takes input (stdout from another command) and prints only lines that match.
- First, it tries to find `hello`.
- If `grep` **finds nothing** (exit code ≠ 0), then the right-hand command after `||` runs → `systemctl list-timers --all | head -5`.
- If `hello` timer is missing, show the first 5 timers.

---

## Auto-recovery

A service that crashes, and systemd brings it back up:

```bash
leprecha@Ubuntu-DevOps:~$ sudo tee /etc/systemd/system/flaky.service >/dev/null <<'UNIT'
> [Unit]
> Description=Flaky demo (restarts on failure)
> 
> [Service]
> Type=simple
> ExecStart=/bin/bash -lc 'echo start; sleep 2; echo crash >&2; exit 1'
> Restart=on-failure
> RestartSec=3s
> UNIT
```

```bash
leprecha@Ubuntu-DevOps:~$ sudo systemctl daemon-reload
leprecha@Ubuntu-DevOps:~$ sudo systemctl start flaky
leprecha@Ubuntu-DevOps:~$ sleep 7
leprecha@Ubuntu-DevOps:~$ systemctl status flaky | sed -n '1,12p'
● flaky.service - Flaky demo (restarts on failure)
     Loaded: loaded (/etc/systemd/system/flaky.service; static)
     Active: active (running) since Mon 2025-08-25 20:03:23 IST; 1s ago
   Main PID: 13873 (bash)
      Tasks: 2 (limit: 18465)
     Memory: 704.0K (peak: 4.3M)
        CPU: 28ms
     CGroup: /system.slice/flaky.service
             ├─13873 /bin/bash -lc "echo start; sleep 2; echo crash >&2; exit 1"
             └─13891 sleep 2

Aug 25 20:03:20 Ubuntu-DevOps systemd[1]: flaky.service: Failed with result 'exit-code'.
leprecha@Ubuntu-DevOps:~$ systemctl show -p NRestarts,ExecMainStatus flaky
NRestarts=8
ExecMainStatus=1
leprecha@Ubuntu-DevOps:~$ journalctl -u flaky -n 20 --no-pager
Aug 25 20:03:52 Ubuntu-DevOps systemd[1]: flaky.service: Main process exited, code=exited, status=1/FAILURE
Aug 25 20:03:52 Ubuntu-DevOps systemd[1]: flaky.service: Failed with result 'exit-code'.
Aug 25 20:03:55 Ubuntu-DevOps systemd[1]: flaky.service: Scheduled restart job, restart counter is at 9.
Aug 25 20:03:55 Ubuntu-DevOps systemd[1]: Started flaky.service - Flaky demo (restarts on failure).
Aug 25 20:03:55 Ubuntu-DevOps bash[13972]: start
Aug 25 20:03:57 Ubuntu-DevOps bash[13972]: crash
Aug 25 20:03:57 Ubuntu-DevOps systemd[1]: flaky.service: Main process exited, code=exited, status=1/FAILURE
Aug 25 20:03:57 Ubuntu-DevOps systemd[1]: flaky.service: Failed with result 'exit-code'.
Aug 25 20:04:00 Ubuntu-DevOps systemd[1]: flaky.service: Scheduled restart job, restart counter is at 10.
Aug 25 20:04:00 Ubuntu-DevOps systemd[1]: Started flaky.service - Flaky demo (restarts on failure).
Aug 25 20:04:00 Ubuntu-DevOps bash[13985]: start
Aug 25 20:04:02 Ubuntu-DevOps bash[13985]: crash
Aug 25 20:04:02 Ubuntu-DevOps systemd[1]: flaky.service: Main process exited, code=exited, status=1/FAILURE
Aug 25 20:04:02 Ubuntu-DevOps systemd[1]: flaky.service: Failed with result 'exit-code'.
Aug 25 20:04:05 Ubuntu-DevOps systemd[1]: flaky.service: Scheduled restart job, restart counter is at 11.
Aug 25 20:04:05 Ubuntu-DevOps systemd[1]: Started flaky.service - Flaky demo (restarts on failure).
Aug 25 20:04:05 Ubuntu-DevOps bash[13999]: start
Aug 25 20:04:07 Ubuntu-DevOps bash[13999]: crash
Aug 25 20:04:07 Ubuntu-DevOps systemd[1]: flaky.service: Main process exited, code=exited, status=1/FAILURE
Aug 25 20:04:07 Ubuntu-DevOps systemd[1]: flaky.service: Failed with result 'exit-code'.
leprecha@Ubuntu-DevOps:~$ systemctl status flaky
● flaky.service - Flaky demo (restarts on failure)
     Loaded: loaded (/etc/systemd/system/flaky.service; static)
     Active: activating (auto-restart) (Result: exit-code) since Mon 2025-08-25 20:04:49 IST; 377ms ago
    Process: 14106 ExecStart=/bin/bash -lc echo start; sleep 2; echo crash >&2; exit 1 (code=exited, status=1/FAILURE)
   Main PID: 14106 (code=exited, status=1/FAILURE)
        CPU: 35ms
leprecha@Ubuntu-DevOps:~$ sudo systemctl stop flaky
```

### What created

- `Type=simple`: service is considered started as soon as the main process starts.
- The command prints `start`, sleeps 2s, prints `crash` to **stderr**, exits **1**.
- `Restart=on-failure`: only restarts on non-zero exit/signal.
- `RestartSec=3s`: waits 3 seconds before restarting.

### What the commands do

- `daemon-reload` → reload unit files.
- `start flaky` → kick off the crash loop.
- `sleep 7` → enough time for ~2 cycles (run → crash → 3s wait → run …).
- `status | sed -n '1,12p'` → header: shows active/failed/restarting transitions.
- `show -p NRestarts,ExecMainStatus` → e.g., `NRestarts≈1–2`, `ExecMainStatus=1`.
- `journalctl -u flaky -n 20` → see `start`/`crash` lines and systemd restart messages.
- `systemctl status flaky`→ see the current phase (auto-restart delay).
- `sudo systemctl stop flaky`→ stop the loop.

---

## Mini-hardening for `hello.service`

A bit of isolation without breaking things.

```bash
leprecha@Ubuntu-DevOps:~$ sudo tee /etc/systemd/system/hello.service >/dev/null << 'UNIT'
> [Unit]
> Description=Hello logger (hardened)
> 
> [Service]
> Type=oneshot
> ExecStart=/usr/local/bin/hello.sh
> ProtectSystem=strict
> ProtectHome=yes
> PrivateTmp=yes
> NoNewPrivileges=yes
> UNIT
```

Set:

- **ProtectSystem=strict** — entire root FS **read-only** (except API mounts).
- **ProtectHome=yes** — no access to `/home`, `/root`, `/run/user/*`.
- **PrivateTmp=yes** — **private /tmp** namespace.
- **NoNewPrivileges=yes** — process cannot gain privileges.
- **Type=oneshot** — run once and exit.

---

```bash
leprecha@Ubuntu-DevOps:~$ sudo systemctl daemon-reload
leprecha@Ubuntu-DevOps:~$ sudo systemctl restart hello.service
leprecha@Ubuntu-DevOps:~$ systemctl status hello.service | sed -n '1,12p'
○ hello.service - Hello logger (hardened)
     Loaded: loaded (/etc/systemd/system/hello.service; static)
     Active: inactive (dead)

Aug 25 20:34:08 Ubuntu-DevOps systemd[1]: Finished hello.service - Hello logger (oneshot).
Aug 25 20:39:20 Ubuntu-DevOps systemd[1]: Starting hello.service - Hello logger (oneshot)...
Aug 25 20:39:20 Ubuntu-DevOps systemd[1]: hello.service: Deactivated successfully.
Aug 25 20:39:20 Ubuntu-DevOps systemd[1]: Finished hello.service - Hello logger (oneshot).
Aug 25 20:44:21 Ubuntu-DevOps systemd[1]: Starting hello.service - Hello logger (oneshot)...
Aug 25 20:44:21 Ubuntu-DevOps systemd[1]: hello.service: Deactivated successfully.
Aug 25 20:44:21 Ubuntu-DevOps systemd[1]: Finished hello.service - Hello logger (oneshot).
Aug 25 20:55:05 Ubuntu-DevOps systemd[1]: Starting hello.service - Hello logger (hardened)...
leprecha@Ubuntu-DevOps:~$ systemctl show -p ExecMainStatus hello.service
ExecMainStatus=0
```

What we seeing:

- Header **`○ … Active: inactive (dead)`** — hollow dot means the unit is **loaded but not currently active**. For `Type=oneshot` it runs and **exits immediately**.
- Logs show `Starting` → `Deactivated successfully` → `Finished` — i.e., **successful exit (0)**.

---

## Further hardening:

```bash
SystemCallFilter=@system-service @basic-io @file-system @network-io
SystemCallArchitectures=native
CapabilityBoundingSet=
AmbientCapabilities=
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictNamespaces=yes
LockPersonality=yes
ProtectClock=yes
ProtectProc=invisible
ProcSubset=pid
```

### System call restrictions

- `SystemCallFilter=@system-service @basic-io @file-system @network-io`
    
    Allows the process only these groups of **system calls** (`syscalls`). Everything else will be **blocked** → protects against exploits and unwanted behavior.
    
    Groups:
    
    - `@system-service` — basic set for normal daemons;
    - `@basic-io` — input/output (read/write files, sockets, etc.);
    - `@file-system` — filesystem operations;
    - `@network-io` — networking operations.
- `SystemCallArchitectures=native`
    
    Only allows syscalls for the **native kernel architecture** (e.g., x86_64). If the process tries to use syscalls for a different ABI → they’ll be blocked. This prevents attackers from abusing “alternative” syscall ABIs.
    

---

### Dropping privileges

- `CapabilityBoundingSet=`
    
    Empty → the service has **no Linux capabilities at all** (can’t bind to privileged ports, mount filesystems, change time, etc.).
    
- `AmbientCapabilities=`
    
    Also empty → no capabilities can be passed down to child processes.
    

---

### Kernel and environment protection

- `ProtectKernelTunables=yes`
    
    Prevents the process from changing kernel tunables in `/proc/sys` or `/sys`.
    
- `ProtectKernelModules=yes`
    
    Prevents loading/unloading kernel modules.
    
- `ProtectControlGroups=yes`
    
    Prevents access to `cgroups`.
    
- `RestrictNamespaces=yes`
    
    Prevents the process from creating its own namespaces (via `unshare`, `clone`, etc.). Useful against container breakout exploits.
    
- `LockPersonality=yes`
    
    Prevents changing the **personality** (execution domain, e.g. running in old Linux compatibility mode).
    
- `ProtectClock=yes`
    
    Prevents the process from changing the system clock.
    

---

### /proc restrictions

- `ProtectProc=invisible`
    
    Makes `/proc` only show the service’s own processes; other processes are hidden.
    
- `ProcSubset=pid`
    
    Only a limited subset of `/proc` is available (`/proc/[pid]`). The rest is hidden.
    

---

## Bottom line

This is an extremely strict **sandboxing setup for a systemd service**. It:

- strips away all capabilities,
- forbids touching the kernel, modules, or cgroups,
- heavily restricts `/proc` and syscalls,
- only allows minimal file and network I/O.

The service will live with the bare minimum privileges.

---

## Transient unit (without a file on disk)

Useful for one-off tasks and debugging.

`sudo systemd-run --unit=now-echo --property=MemoryMax=50M \
/bin/bash -lc 'echo transient $(date) | systemd-cat -t now-echo'`

```bash
leprecha@Ubuntu-DevOps:~$ sudo systemd-run --unit=now-echo --property=MemoryMax=50M \
  /bin/bash -lc 'echo transient $(date) | systemd-cat -t now-echo'
Running as unit: now-echo.service; invocation ID: c3e65a1b9568424898789390f6d89914
leprecha@Ubuntu-DevOps:~$ journalctl -u now-echo -n 5 --no-pager
Aug 25 21:14:25 Ubuntu-DevOps systemd[1]: Started now-echo.service - /bin/bash -lc "echo transient \$(date) | systemd-cat -t now-echo".
Aug 25 21:14:25 Ubuntu-DevOps systemd[1]: now-echo.service: Deactivated successfully.
leprecha@Ubuntu-DevOps:~$ journalctl -t now-echo -n 5 --no-pager
Aug 25 21:14:25 Ubuntu-DevOps now-echo[15925]: transient Mon Aug 25 09:14:25 PM IST 2025
```

### What it does

- **`systemd-run`** → starts a *transient unit* (not saved in `/etc/systemd/system/`).
- **`-unit=now-echo`** → unit name = `now-echo.service`.
- **`-property=MemoryMax=50M`** → cgroup memory limit = 50 MB.
- **Command**: bash prints `transient <date>`, pipes to `systemd-cat` with tag `now-echo`.

### Notes

- Unit is **transient**: it disappears after exit.
- Logs remain available with `journalctl -u now-echo`.
- But the actual `echo transient $(date)` line is missing from `journalctl -u now-echo`, because it was written with `systemd-cat` using the tag **`now-echo`**.
- Great for testing resource limits and sandboxing on the fly.

---

## Persistent journald logs

- **`-u`** → *unit.*
    
    Show logs for a specific systemd unit (e.g. `-u ssh.service`).
    
- **`-p`** → *priority.*
    
    Filter by log level / severity (`emerg`, `alert`, `crit`, `err`, `warning`, `notice`, `info`, `debug`). Example: `-p warning`.
    
- **`-b`** → *boot.*
    
    Show messages from the current boot (or a specific one with `-b -1`, etc.).
    
- **`-f`** → *follow.*
    
    Follow new log entries in real time (like `tail -f`).
    
- **`-t`** → *identifier (tag).*
    
    Filter by syslog identifier/program name (e.g. `-t sshd`).
    

So that logs survive reboots.

```bash
leprecha@Ubuntu-DevOps:~$ sudo mkdir -p /var/log/journal
leprecha@Ubuntu-DevOps:~$ sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/persistent.conf >/dev/null <<'CFG'
[Journal]
Storage=persistent
SystemMaxUse=200M
RuntimeMaxUse=50M
SystemMaxFileSize=50M
MaxFileSec=1month
Compress=yes
Seal=yes
CFG
leprecha@Ubuntu-DevOps:~$ sudo systemctl restart systemd-journald
leprecha@Ubuntu-DevOps:~$ journalctl --disk-usage
Archived and active journals take up 199.8M in the file system.
```

### What we did

1. Created `/var/log/journal` → tells journald to use disk-based storage. Default was `/run/log/journal` (RAM, lost at reboot).
2. Restarted `systemd-journald` → now logs persist across reboots.
3. `journalctl --disk-usage` → shows how much disk space logs take.

### Why it’s useful

- **On servers** — keep logs after reboot.
- **Debugging** — access previous boots: `journalctl -b -1`

---

**Cleanup**:

```bash
sudo systemctl disable --now hello.timer
sudo systemctl stop hello.service flaky || true
sudo rm -f /etc/systemd/system/{hello.service,hello.timer,flaky.service}
sudo systemctl daemon-reload
```

---

## Summary

- Service+Timer working; logs verified; (optional) restart policy & hardening explored.

**Artifacts:** `labs/day5/hello.service`, `labs/day5/flaky.service`, `labs/day5/hello.timer` `tools/hello.sh`