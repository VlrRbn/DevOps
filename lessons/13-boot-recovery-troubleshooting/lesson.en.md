# lesson_13

# Boot and Recovery: `journalctl -b`, `systemctl --failed`, `dmesg`, `rescue/emergency`

**Date:** 2026-02-20
**Topic:** diagnosing post-boot problems and running a safe, repeatable recovery triage flow.  
**Daily goal:** Learn to answer "why did the host boot into degraded/problem state" and execute a practical runbook.

---

## 0. Prerequisites

Check base dependencies:

```bash
command -v systemctl journalctl findmnt lsblk dmesg
```

Optional for extended boot config diagnostics:

```bash
command -v grubby update-grub || echo "grub tools differ by distro"
```

Critical safety rules:

- use `rescue`/`emergency` only from local console/VM;
- on remote hosts without out-of-band access, do not run `systemctl isolate rescue.target`;
- create config snapshot before risky changes.

---

## 1. Core Concepts

### 1.1 What "system booted" actually means

A successful boot does not always mean system health is good.

The host can boot while still being:

- `degraded` (failed units exist);
- affected by broken `fstab` mounts;
- running services in crash loops.

### 1.2 Why `journalctl -b` is primary

`journalctl -b` shows current boot events, and `journalctl -b -1` shows previous boot.

This is the fastest way to inspect what happened during the exact boot window.

### 1.3 `systemd` run state and failed units

Two quick checks:

- `systemctl is-system-running` — global system state (`running/degraded/...`);
- `systemctl list-units --failed` — exact failed units.

### 1.4 Where `dmesg` fits

`journalctl` is strong for service/user-space timelines, while `dmesg` exposes kernel-level warnings/errors.

If issue is driver/disk/filesystem/kernel path, `dmesg` is often the quickest signal.

### 1.5 `findmnt --verify` and `fstab`

Broken `/etc/fstab` entries can cause long boot delays, degraded state, or emergency mode.

`findmnt --verify` is a fast consistency check for mount metadata.

### 1.6 Rescue vs Emergency

- `rescue.target` — minimal rescue environment (basic services + root shell);
- `emergency.target` — ultra-minimal mode (almost no services).

Practical use:

- rescue for service/mount repair with minimal stack alive;
- emergency for deep low-level repair with minimal interference.

### 1.7 Standard triage workflow

1. run state + failed units;
2. boot journal (`-b`, and `-b -1` when needed);
3. kernel errors (`dmesg`);
4. mount/fstab verify;
5. only then apply fixes.

---

## 2. Command Priority (What to Learn First)

### Core (must know now)

- `systemctl is-system-running`
- `systemctl list-units --failed --no-pager --plain`
- `journalctl -b -p err..alert --no-pager`
- `journalctl -b -1 -p err..alert --no-pager`
- `findmnt --verify`
- `dmesg --level=err,warn`

### Optional (after core)

- `systemctl status <unit>`
- `journalctl -u <unit> --since ...`
- `systemctl list-dependencies rescue.target`
- `cat /proc/cmdline`

### Advanced (ops-grade)

- controlled `rescue/emergency` switching (local console only)
- rollback-safe boot config changes
- incident runbook: symptom -> check -> action

---

## 3. Core Commands: What / Why / When

### `systemctl is-system-running`

- **What:** global systemd run state.
- **Why:** quickly detect degraded/offline condition.
- **When:** first triage command.

```bash
systemctl is-system-running
```

### `systemctl list-units --failed --no-pager --plain`

- **What:** failed unit list.
- **Why:** move from symptom to concrete failing objects.
- **When:** right after run-state check.

```bash
systemctl list-units --failed --no-pager --plain
```

### `journalctl -b -p err..alert --no-pager`

- **What:** errors from current boot.
- **Why:** remove noise and focus on critical messages.
- **When:** after failed-unit listing.

```bash
journalctl -b -p err..alert --no-pager | sed -n '1,120p'
```

### `journalctl -b -1 -p err..alert --no-pager`

- **What:** errors from previous boot.
- **Why:** useful when issue happened during earlier reboot.
- **When:** when current boot logs are not enough.

```bash
journalctl -b -1 -p err..alert --no-pager | sed -n '1,120p'
```

### `findmnt --verify`

- **What:** mount/fstab metadata verification.
- **Why:** fast way to detect bad mount declarations.
- **When:** when boot/mount behavior looks suspicious.

```bash
findmnt --verify
```

### `dmesg --level=err,warn`

- **What:** kernel warnings/errors.
- **Why:** detect low-level device/fs/driver issues.
- **When:** when journal suggests kernel/IO path problem.

```bash
sudo dmesg --level=err,warn | tail -n 80
```

---

## 4. Optional Commands (After Core)

Optional block helps move from global health to root cause in a specific unit.

### 4.1 `systemctl status <unit>`

- **What:** unit state plus recent logs.
- **Why:** understand exact failure mode.
- **When:** right after identifying failed unit.

```bash
systemctl status ssh --no-pager | sed -n '1,40p'
```

### 4.2 `journalctl -u <unit> --since ...`

- **What:** unit-scoped timeline.
- **Why:** isolate relevant logs from full boot noise.
- **When:** crash-loop and timeout analysis.

```bash
journalctl -u ssh --since "-30 min" --no-pager | tail -n 80
```

### 4.3 `systemctl list-dependencies rescue.target`

- **What:** rescue target dependency tree.
- **Why:** know what actually starts in rescue mode.
- **When:** before planned recovery drills.

```bash
systemctl list-dependencies rescue.target --no-pager
```

### 4.4 `cat /proc/cmdline`

- **What:** active kernel boot parameters.
- **Why:** confirm what kernel args are truly applied.
- **When:** boot-parameter regression checks.

```bash
cat /proc/cmdline
```

### What to do in Optional in practice

1. Pick one failed unit.
2. Collect `status` and unit-specific journal.
3. Match timestamps against boot journal.
4. Write a clear hypothesis before changing anything.

---

## 5. Advanced Topics (Ops-Grade)

### 5.1 Recovery snapshot before changes

Before editing boot/fstab/systemd config, snapshot:

- `/etc/fstab`, `/etc/default/grub`, `/etc/systemd/system/*`;
- current boot diagnostics;
- failed-unit list.

This gives fast rollback context.

### 5.2 Controlled recovery flow

Standard flow:

1. diagnose (read-only);
2. isolate one likely root cause;
3. apply smallest safe fix;
4. verify (`is-system-running`, `--failed`, boot journal);
5. document outcome.

### 5.3 `rescue/emergency` only with safe access

Recovery targets may terminate SSH sessions.

Rule:

- without local console/VM console/IPMI/SSM-like access, do not isolate recovery targets remotely.

### 5.4 What to do if `fstab` is broken

Safe fast path:

1. get shell (rescue/emergency/local console);
2. rollback problematic entries;
3. run `findmnt --verify`;
4. `systemctl daemon-reload`;
5. reboot and verify run-state.

### 5.5 Symptom to action map

| Symptom | Check | Typical cause | Action |
|---|---|---|---|
| `degraded` after boot | `is-system-running`, `--failed` | one or more unit failures | triage failed units and fix root cause |
| long boot | `journalctl -b`, `findmnt --verify` | mount timeout/fstab issue | fix fstab and validate options |
| service restart loop | `status`, `journalctl -u` | bad config/env/permissions | correct config and validate dependencies |
| unclear boot fail | `dmesg`, `journalctl -b -1` | kernel/fs/device level issue | localize failing layer and repair |

### 5.6 Advanced step-by-step

```bash
# 1) baseline
systemctl is-system-running
systemctl list-units --failed --no-pager --plain

# 2) boot errors
journalctl -b -p err..alert --no-pager | sed -n '1,120p'

# 3) mount/fstab
findmnt --verify

# 4) kernel layer
sudo dmesg --level=err,warn | tail -n 80
```

---

## 6. Scripts in This Lesson

Scripts here accelerate triage and documentation; they do not replace understanding manual flow.

### 6.1 Manual Core run (do once without scripts)

```bash
# 1) global state
systemctl is-system-running
systemctl list-units --failed --no-pager --plain

# 2) boot errors (current + previous)
journalctl -b -p err..alert --no-pager | sed -n '1,120p'
journalctl -b -1 -p err..alert --no-pager | sed -n '1,120p'

# 3) mount/fstab consistency
findmnt --verify

# 4) kernel warnings/errors
sudo dmesg --level=err,warn | tail -n 80
```

### 6.2 Scripts (automation)

```bash
chmod +x lessons/13-boot-recovery-troubleshooting/scripts/*.sh

lessons/13-boot-recovery-troubleshooting/scripts/boot-health-check.sh
lessons/13-boot-recovery-troubleshooting/scripts/boot-triage.sh --boot 0 --since "-2h"
lessons/13-boot-recovery-troubleshooting/scripts/recovery-snapshot.sh --out-dir /tmp
```

### 6.3 What each script does

| Script | What it does | When to run |
|---|---|---|
| `boot-health-check.sh` | quick health baseline | first triage step |
| `boot-triage.sh` | extended boot report (journal + failed units + dmesg + findmnt) | when you need evidence and timeline |
| `recovery-snapshot.sh` | saves configs + diagnostics to snapshot dir | before risky changes and for incident records |

---

## 7. Mini Lab (Core Path)

Goal: complete full boot-triage cycle without changing system state.

```bash
# quick health
lessons/13-boot-recovery-troubleshooting/scripts/boot-health-check.sh

# focused triage
lessons/13-boot-recovery-troubleshooting/scripts/boot-triage.sh --boot 0 --since "-1h"

# collect snapshot
lessons/13-boot-recovery-troubleshooting/scripts/recovery-snapshot.sh --out-dir /tmp
```

Success criteria:

- explicit run-state and failed-unit view (or confirmation none failed);
- boot-level evidence captured from `journalctl -b`;
- snapshot artifacts exist under `/tmp/recovery-snapshot_*`.

---

## 8. Extended Lab (Optional + Advanced)

### 8.1 Previous boot analysis

```bash
lessons/13-boot-recovery-troubleshooting/scripts/boot-triage.sh --boot -1 --strict
```

### 8.2 Unit-level drill

```bash
# replace ssh with real failed unit in your host
systemctl status ssh --no-pager | sed -n '1,60p'
journalctl -u ssh --since "-2h" --no-pager | tail -n 120
```

### 8.3 Recovery mode drill (VM/local console only)

```bash
# WARNING: remote SSH session can be lost
sudo systemctl isolate rescue.target
# return to normal target:
sudo systemctl default
```

### 8.4 Snapshot before change

```bash
lessons/13-boot-recovery-troubleshooting/scripts/recovery-snapshot.sh --out-dir /tmp/lesson13-artifacts
ls -la /tmp/lesson13-artifacts
```

---

## 9. Cleanup

This lesson is mostly read-only, so cleanup is minimal.

Optional artifact cleanup:

```bash
rm -rf /tmp/recovery-snapshot_* /tmp/lesson13-artifacts/recovery-snapshot_* 2>/dev/null || true
```

---

## 10. Lesson Summary

- **What I learned:** how to read post-boot issues through `systemd` + `journalctl -b` + `dmesg` + `findmnt --verify`.
- **What I practiced:** reproducible triage workflow and recovery snapshots before risky changes.
- **What I can do manually now:** localize degraded/boot issues to the correct layer (unit/mount/kernel) with evidence.
- **Next step:** lesson 14 (performance triage): CPU/RAM/IO bottleneck analysis with operational metrics.
- **Repo artifacts:** `lessons/13-boot-recovery-troubleshooting/scripts/`, `lessons/13-boot-recovery-troubleshooting/scripts/README.md`.