# lesson_05

# Processes, Systemd Services, Timers, and Journalctl

**Date:** 2025-08-25  
**Topic:** Process inspection, signals, systemd unit lifecycle, timers, and logging with journald  
**Daily goal:** Learn how to inspect running processes, manage systemd services/timers, and debug behavior through logs.
**Bridge:** [05-07 Operations Bridge](../00-foundations-bridge/05-07-operations-bridge.md) for missing practical gaps after lessons 5-7.

---

## 1. Core Concepts

### 1.1 Process basics

A process is a running program instance with:

- PID (process ID)
- PPID (parent process ID)
- state (`R`, `S`, `D`, `Z`, etc.)
- CPU/memory usage

### 1.2 Signals

Signals are async control messages to processes.

- `SIGTERM` (15): graceful stop request
- `SIGKILL` (9): force kill (cannot be caught/ignored)

Rule: always try `SIGTERM` first.

### 1.3 systemd units

`systemd` manages units (`.service`, `.timer`, `.socket`, ...).

For services, typical lifecycle states:

- `active (running)`
- `inactive (dead)`
- `failed`
- `activating` / `deactivating`

#### Where unit files and scripts live

- `/usr/local/bin` - executable scripts/binaries (what to run).
- `/etc/systemd/system` - admin-managed unit files and overrides (how/when to run it).

In this lesson, the chain is:

- script: `/usr/local/bin/hello.sh`
- unit: `/etc/systemd/system/hello.service`
- timer: `/etc/systemd/system/hello.timer`

After editing unit files, run `systemctl daemon-reload` so systemd re-reads configuration.

### 1.4 journald

`journald` stores structured logs for units and system events.

Most useful filters:

- `-u <unit>` by unit
- `-p <priority>` by severity
- `-b` by boot
- `-f` follow mode
- `-t` by identifier tag

### 1.5 How to read `priority` in `journalctl`

Severity levels are from 0 to 7:

- `0` `emerg` - system is unusable
- `1` `alert` - immediate action required
- `2` `crit` - critical condition
- `3` `err` - error
- `4` `warning` - warning
- `5` `notice` - important normal event
- `6` `info` - informational event
- `7` `debug` - debug detail

Most practical filters:

- `-p warning` - warnings and all more severe events
- `-p err..alert` - only error/critical range

```bash
journalctl -u cron -p warning --since "1 hour ago" --no-pager
journalctl -u cron -p err..alert --since today --no-pager
```

### 1.6 Service triage flow (quick path)

When a service behaves unexpectedly, use this order:

1. `systemctl status <unit> --no-pager` for current state and recent context.
2. `journalctl -u <unit> -n 50 --no-pager` for latest events.
3. `journalctl -u <unit> --since "30 min ago" -p warning --no-pager` for filtered problems.
4. `systemctl cat <unit>` and `systemctl show -p ... <unit>` to confirm effective config and runtime props.
5. If needed, restart and watch live: `journalctl -fu <unit>`.

This answers three key questions fast: is it running, why did it fail, and which config is actually applied.

---

## 2. Command Priority (What to Learn First)

### Core (must know now)

- `ps aux --sort=-%cpu`, `ps aux --sort=-%mem`
- `ps -p <pid> -o ...`
- `pstree -p`
- `kill -SIGTERM <pid>` then `kill -SIGKILL <pid>` if needed
- `systemctl status <unit>`
- `systemctl cat <unit>`
- `systemctl show -p ... <unit>`
- `journalctl -u <unit> -n 20 --no-pager`
- `journalctl -fu <unit>`

### Optional (useful after core)

- `hostnamectl`
- `systemctl list-units --type=service --state=running`
- `systemctl is-system-running`
- `systemctl list-timers --all`
- `systemctl --failed`
- `systemd-analyze time|blame|critical-chain`

### Advanced (deeper operations)

- drop-in overrides in `/etc/systemd/system/<unit>.service.d/`
- own `oneshot` service + timer
- restart policy (`Restart=on-failure`)
- basic/extended service hardening directives
- transient units via `systemd-run`
- persistent journald configuration

---

## 3. Core Commands: What / Why / When

### `ps aux --sort=-%cpu` and `ps aux --sort=-%mem`

- **What:** process list sorted by CPU or memory usage.
- **Why:** fastest way to identify resource-heavy processes.
- **When:** host is slow, fans spinning, or memory pressure suspected.

```bash
ps aux --sort=-%cpu | head
ps aux --sort=-%mem | head
```

### `pstree -p`

- **What:** process tree with parent-child relations and PIDs.
- **Why:** helps understand who spawned which process.
- **When:** tracing service subprocesses or orphaned workers.

```bash
pstree -p | head -n 20
```

### `ps -p <pid> -o ...`

- **What:** focused details for one PID.
- **Why:** precise inspection without noisy full process list.
- **When:** after finding suspicious PID.

```bash
S=$(sleep 300 & echo $!)
ps -p "$S" -o pid,ppid,stat,etime,cmd
```

### `kill -SIGTERM` then `kill -SIGKILL`

- **What:** stop process gracefully, then forcibly if needed.
- **Why:** reduces corruption risk compared to immediate kill -9.
- **When:** stopping stuck process or testing signal behavior.

```bash
kill -SIGTERM "$S"
sleep 1
ps -p "$S" -o pid,stat || echo "terminated"

# only if still alive
kill -SIGKILL "$S"
```

### `systemctl status <unit>`

- **What:** current state, PID, recent logs, load status.
- **Why:** first entry point for service troubleshooting.
- **When:** any service start/restart/failure issue.

```bash
systemctl status cron
```

### `systemctl cat <unit>`

- **What:** full effective unit config + drop-ins.
- **Why:** confirms what systemd actually reads.
- **When:** service behavior differs from expected config.

```bash
systemctl cat cron
```

### `systemctl show -p ... <unit>`

- **What:** selected machine-readable properties.
- **Why:** quick scriptable checks.
- **When:** extracting PID, restart policy, unit file path, states.

```bash
systemctl show -p FragmentPath,UnitFileState,ActiveState,SubState,MainPID,ExecStart,Restart,RestartUSec cron
```

### `journalctl -u ...` and `journalctl -fu ...`

- **What:** historical and live logs for a unit.
- **Why:** root source for failure reason and sequence of events.
- **When:** service fails, restarts, hangs, or acts unexpectedly.

```bash
journalctl -u cron --since "15 min ago" --no-pager
journalctl -fu cron
```

---

## 4. Optional Commands (After Core)

### `hostnamectl`

- **What:** system identity and host metadata.
- **Why:** useful inventory snapshot during diagnostics.
- **When:** documenting environment before troubleshooting.

```bash
hostnamectl
```

### `systemctl list-units --type=service --state=running`

- **What:** currently running services.
- **Why:** quick service surface overview.
- **When:** checking baseline after boot/deploy.

```bash
systemctl list-units --type=service --state=running | head -n 5
```

### `systemctl is-system-running`

- **What:** overall systemd health (`running`, `degraded`, ...).
- **Why:** one-word health signal.
- **When:** quick post-boot validation.

```bash
systemctl is-system-running
```

### `systemctl list-timers --all`

- **What:** timer schedule + last/next trigger info.
- **Why:** audit scheduled jobs and missed runs.
- **When:** timer didn't fire or fired unexpectedly.

```bash
systemctl list-timers --all | head -n 10
```

### `systemctl --failed`

- **What:** list of failed units.
- **Why:** first triage list after incidents.
- **When:** system status is degraded.

```bash
systemctl --failed
```

### `systemd-analyze time|blame|critical-chain`

- **What:** boot timing metrics and dependency chain.
- **Why:** boot performance and startup dependency debugging.
- **When:** slow boot investigation.

```bash
systemd-analyze time
systemd-analyze blame | head -n 15
systemd-analyze critical-chain
```

---

## 5. Advanced Topics (Services, Timers, Hardening)

### 5.1 Safe unit customization via drop-in override

Never edit distro unit file directly. Use drop-in override:

```bash
sudo mkdir -p /etc/systemd/system/cron.service.d
printf "[Service]\nEnvironment=HELLO=world\n" | sudo tee /etc/systemd/system/cron.service.d/override.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl restart cron
systemctl cat cron
```

Why this is preferred:

- package upgrades do not overwrite your custom file
- changes are explicit and reversible

### 5.2 Build own service + timer (hello logger every 5 min)

#### Script

```bash
sudo tee /usr/local/bin/hello.sh >/dev/null <<'SH'
#!/usr/bin/env bash
echo "[hello] $(date '+%F %T') $(hostname)" | systemd-cat -t hello -p info
SH
sudo chmod +x /usr/local/bin/hello.sh
```

#### Service unit (`oneshot`)

```bash
sudo tee /etc/systemd/system/hello.service >/dev/null <<'UNIT'
[Unit]
Description=Hello logger (oneshot)

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hello.sh
UNIT
```

#### Timer unit

```bash
sudo tee /etc/systemd/system/hello.timer >/dev/null <<'UNIT'
[Unit]
Description=Run hello.service every 5 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=hello.service

[Install]
WantedBy=timers.target
UNIT
```

#### Enable and verify

```bash
sudo systemctl daemon-reload
sudo systemctl start hello.service
sudo systemctl enable --now hello.timer
systemctl list-timers --all | grep hello || systemctl list-timers --all | head -n 5
journalctl -u hello.service --since "10 min ago" -n 20 --no-pager
journalctl -t hello -n 20 --no-pager
```

### 5.3 Auto-recovery demo (`Restart=on-failure`)

```bash
sudo tee /etc/systemd/system/flaky.service >/dev/null <<'UNIT'
[Unit]
Description=Flaky demo (restarts on failure)

[Service]
Type=simple
ExecStart=/bin/bash -lc 'echo start; sleep 2; echo crash >&2; exit 1'
Restart=on-failure
RestartSec=3s
UNIT

sudo systemctl daemon-reload
sudo systemctl start flaky
sleep 7
systemctl show -p NRestarts,ExecMainStatus flaky
journalctl -u flaky -n 20 --no-pager
```

### 5.4 Hardening quick set for `hello.service`

```ini
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
```

Meaning:

- stricter FS write access
- no home dir access
- isolated `/tmp`
- no privilege gain via exec

Extended hardening examples (use with testing):

```ini
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

### 5.5 Transient unit (no file on disk)

```bash
sudo systemd-run --unit=now-echo --property=MemoryMax=50M \
  /bin/bash -lc 'echo transient $(date) | systemd-cat -t now-echo'

journalctl -u now-echo -n 10 --no-pager
journalctl -t now-echo -n 10 --no-pager
```

### 5.6 Persistent journald storage

```bash
sudo mkdir -p /var/log/journal
sudo mkdir -p /etc/systemd/journald.conf.d
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

sudo systemctl restart systemd-journald
journalctl --disk-usage
```

---

## 6. Mini-lab (Core Path)

### Goal

Perform baseline process/service/log diagnostics with minimal commands.

### Steps

1. Find CPU and memory heavy processes.
2. Start one test process and inspect it by PID.
3. Terminate it gracefully.
4. Inspect `cron` service state and logs.

```bash
ps aux --sort=-%cpu | head
ps aux --sort=-%mem | head

sleep 300 &
S=$!
ps -p "$S" -o pid,ppid,stat,etime,cmd
kill -SIGTERM "$S"
sleep 1
ps -p "$S" -o pid,stat || echo "terminated"

systemctl status cron | sed -n '1,15p'
systemctl cat cron
journalctl -u cron --since "15 min ago" --no-pager | tail -n 20
```

Validation checklist:

- can identify top process by `%CPU` and `%MEM`
- can inspect and terminate test PID
- can read service status and related logs

---

## 7. Extended Lab (Optional + Advanced)

### 7.1 Build and run hello service/timer

Run all commands from section 5.2 and verify:

- `hello.timer` appears in `list-timers`
- `journalctl -u hello.service` has start/finish events
- `journalctl -t hello` has custom payload line

### 7.2 Restart policy with flaky service

Run section 5.3 and verify:

- `NRestarts` increases
- `ExecMainStatus=1`
- logs show crash and scheduled restart loop

Stop loop after test:

```bash
sudo systemctl stop flaky
```

### 7.3 Hardening pass

1. Add quick hardening directives to `hello.service`.
2. Reload and run service.
3. Verify successful execution and `ExecMainStatus=0`.

```bash
sudo systemctl daemon-reload
sudo systemctl restart hello.service
systemctl show -p ExecMainStatus hello.service
```

### 7.4 Transient unit test

Run section 5.5 and verify both unit logs and identifier-tag logs.

### 7.5 Journald persistence

Run section 5.6 and confirm non-volatile storage and disk usage.

---

## 8. Cleanup

```bash
sudo systemctl disable --now hello.timer 2>/dev/null || true
sudo systemctl stop hello.service flaky now-echo 2>/dev/null || true
sudo rm -f /etc/systemd/system/{hello.service,hello.timer,flaky.service}
sudo rm -f /usr/local/bin/hello.sh
sudo rm -f /etc/systemd/journald.conf.d/persistent.conf
sudo systemctl daemon-reload
```

---

## 9. Lesson Summary

- **What I learned:** process inspection flow, signal strategy, and core systemd/journalctl diagnostics.
- **What I practiced:** service introspection (`status/cat/show`), log filtering, and timer-based automation.
- **Advanced skills:** safe drop-ins, restart policy behavior, transient units, and journald persistence.
- **Security focus:** service hardening controls and least-privilege runtime behavior.
- **Repo artifacts:** ready-to-run scripts and unit templates in `lessons/05-processes-systemd-services/scripts/`.
- **Next step:** package custom units and scripts into `lessons/05-processes-systemd-services/` artifacts for reuse.
