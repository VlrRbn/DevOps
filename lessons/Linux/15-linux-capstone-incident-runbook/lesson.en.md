# lesson_15

# Linux Capstone: Incident Runbook, Evidence-First Triage, Handoff

**Date:** 2026-02-22
**Topic:** final Linux practice: combine boot/process/storage/network skills into one operational incident workflow.  
**Daily goal:** run an end-to-end sequence: health gate -> triage -> snapshot -> clear conclusions and handoff.

---

## 0. Prerequisites

Check baseline dependencies:

```bash
command -v bash awk free df uptime nproc vmstat ip ss lsblk findmnt journalctl tar
```

Optional for deeper analysis:

```bash
command -v systemctl iostat pidstat dmesg || echo "optional tools missing"
```

Operational rules:

- collect evidence first, then change system state;
- do not mix diagnostics and remediation in one step;
- take a snapshot before risky changes.

---

## 1. Core Concepts

### 1.1 What capstone means

Capstone is not a new topic; it is integration of previous lessons:

- boot/systemd signals;
- process/resource pressure;
- storage/mount consistency;
- network reachability and listeners;
- reproducible evidence bundle.

### 1.2 Why one runbook matters

Without a runbook, incident response becomes a random command list.
With a runbook you get:

- predictable sequence;
- consistent quality bar;
- clean handoff to another engineer.

### 1.3 Evidence-first workflow

Core pattern:

1. capture current state;
2. fix symptom timeline and observations;
3. only then apply changes.

### 1.4 Minimum useful signal set

For first localization, usually enough:

- run state + failed units;
- load/memory/disk pressure;
- network: default route + listeners;
- journal warnings/errors + kernel hints.

---

## 2. Command Priority (What to Learn First)

### Core (must know now)

- `systemctl is-system-running`
- `systemctl list-units --failed --no-pager --plain`
- `uptime`, `free -h`, `df -h /`, `vmstat 1 5`
- `ip route`, `ss -tulpen`
- `journalctl --since "-2h" -p warning..alert --no-pager`

### Optional (after core)

- `iostat -xz 1 5`
- `pidstat 1 5`
- `findmnt --verify`
- `dmesg --level=err,warn`

### Advanced (ops-grade)

- script-based strict health gate
- triage report for incident ticket/handoff
- snapshot + archive for postmortem evidence

---

## 3. Core Commands: What / Why / When

### `systemctl is-system-running`

- **What:** global system state (`running/degraded/...`).
- **Why:** immediate health signal for platform state.
- **When:** first command in the flow.

```bash
systemctl is-system-running
```

### `systemctl list-units --failed`

- **What:** failed unit list.
- **Why:** move from symptom to concrete failing objects.
- **When:** right after run-state check.

```bash
systemctl list-units --failed --no-pager --plain
```

### `uptime/free/df/vmstat`

- **What:** core resource pressure snapshot.
- **Why:** capture CPU/RAM/disk pressure in one block.
- **When:** baseline before deep diagnostics.

```bash
uptime
free -h
df -h /
vmstat 1 5
```

### `ip route` and `ss -tulpen`

- **What:** route and listener state.
- **Why:** separate network-path issues from service-bind issues.
- **When:** when symptom is "service unreachable".

```bash
ip route
ss -tulpen | sed -n '1,80p'
```

### `journalctl --since ... -p warning..alert`

- **What:** warning/error timeline for selected window.
- **Why:** correlate symptoms with events in time.
- **When:** after baseline checks.

```bash
journalctl --since "-2h" -p warning..alert --no-pager | sed -n '1,200p'
```

---

## 4. Optional Commands (After Core)

### `iostat -xz 1 5`

- **What:** disk latency/utilization details.
- **Why:** confirm or reject IO bottleneck hypothesis.

```bash
iostat -xz 1 5
```

### `pidstat 1 5`

- **What:** sampled per-process activity.
- **Why:** detect short-lived spikes and noisy workloads.

```bash
pidstat 1 5
```

### `findmnt --verify`

- **What:** mount/fstab consistency check.
- **Why:** catch mount metadata issues before reboot impact.

```bash
findmnt --verify
```

### `dmesg --level=err,warn`

- **What:** kernel-level warnings/errors.
- **Why:** confirm low-level device/fs/driver issues.

```bash
sudo dmesg --level=err,warn | tail -n 80
```

---

## 5. Advanced Topics (Ops-Grade)

### 5.1 Incident report structure

Minimum handoff quality bar:

- symptom + impact;
- timeframe;
- key metrics/logs;
- working hypothesis;
- next action + owner.

### 5.2 Strict checks as quality gate

`--strict` does not fix the system, but enforces a minimal readiness bar for automation and runbooks.

### 5.3 Snapshot discipline

Take snapshot before changes and before cleanup so evidence remains intact for post-analysis.

---

## 6. Scripts in This Lesson

### `capstone-health-check.sh`

**What it does:** quick gate for system/resource/network readiness.  
**Why:** get a fast go/no-go signal.  
**When to run:** first step and automation checks (`--strict`).

```bash
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh --strict
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh --json
```

### `capstone-triage.sh`

**What it does:** extended triage report across system/resource/network/log layers.  
**Why:** produce clear evidence and handoff-ready report.  
**When to run:** when root-cause analysis and timeline are required.

```bash
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --seconds 8 --since "-4h"
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --seconds 8 --since "-4h" --save-dir /tmp/lesson15-reports
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --seconds 8 --since "-4h" --json --save-dir /tmp/lesson15-reports
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --strict --save-dir /tmp/lesson15-reports
```

### `capstone-snapshot.sh`

**What it does:** full evidence bundle + `.tar.gz` archive.  
**Why:** preserve state before remediation and support postmortem.
**When to run:** before changes and cleanup.

```bash
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-snapshot.sh
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-snapshot.sh --out-dir /tmp/lesson15-artifacts --since "-4h" --seconds 8
```

---

## 7. Practice (Manual Flow)

### Step 1. Quick gate

```bash
systemctl is-system-running
systemctl list-units --failed --no-pager --plain
uptime
free -h
df -h /
ip route
```

### Step 2. Localization and timeline

```bash
vmstat 1 5
ss -tulpen | sed -n '1,80p'
journalctl --since "-2h" -p warning..alert --no-pager | sed -n '1,200p'
```

### Step 3. Scripted flow

```bash
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh --strict
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --seconds 8 --since "-4h" --save-dir /tmp/lesson15-reports
./lessons/15-linux-capstone-incident-runbook/scripts/capstone-snapshot.sh --out-dir /tmp/lesson15-artifacts --since "-4h" --seconds 8
```

---

## 8. Troubleshooting

### "`systemctl` unavailable / not responding"

Run core resource/network commands and continue triage without systemd-specific sections.
In restricted/container environments unit-level checks may be unavailable.

### "`dmesg` empty or permission denied"

Expected without root on hardened systems.
Run triage/snapshot with `sudo` when kernel context is required.

### "`iostat`/`pidstat` missing"

Optional blocks. Install `sysstat` for deeper sampling:

```bash
sudo apt-get update
sudo apt-get install -y sysstat
```

### "Strict mode fails but services look up"

`--strict` enforces baseline operational thresholds.

---

## 9. Lesson Summary

- **What I learned:** how to combine Linux skills from lessons 1-14 into one incident runbook.
- **What I practiced:** evidence-first triage, strict checks, and reproducible snapshot/handoff workflow.
- **Advanced skills:** symptom-driven analysis with signal/noise separation and hypothesis capture before changes.
- **Operational focus:** minimal risk, predictable workflow, and high-quality artifacts.
- **Repo artifacts:** `lessons/15-linux-capstone-incident-runbook/scripts/`, `lessons/15-linux-capstone-incident-runbook/scripts/README.md`.
