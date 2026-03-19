# lesson_14

# Performance Triage: CPU/RAM/IO, `vmstat`/`iostat`/`pidstat`, snapshot workflow

**Date:** 2026-02-21
**Topic:** practical Linux performance diagnostics without guesswork: find the bottleneck (CPU, memory, disk, process pressure) and collect evidence.  
**Daily goal:** run a reproducible triage flow: quick health-check -> extended triage report -> full incident snapshot archive.

---

## 0. Prerequisites

Check baseline dependencies:

```bash
command -v bash awk nproc free ps uptime vmstat journalctl tar
```

Optional for deeper metrics:

```bash
command -v iostat pidstat mpstat || echo "install sysstat for extended metrics"
```

Critical safety rules:

- collect evidence first, change config second;
- avoid blind tuning based on one number;
- if this is an incident, save a snapshot before cleanup/restart.

---

## 1. Core Concepts

### 1.1 What performance triage means

Performance triage is not "optimization". It is **bottleneck identification**:

- CPU saturation;
- memory pressure and swap thrashing;
- disk IO wait/latency;
- noisy process/service behavior.

### 1.2 Why order matters

A good sequence saves time:

1. global state (uptime/load/memory);
2. top processes;
3. time-sampled metrics (`vmstat`, `iostat`, `pidstat`);
4. archived artifacts for repeatable analysis.

### 1.3 Why `load average` must be normalized

Raw `load` alone does not mean "bad".
Use **load per core** (`load_per_core`):

- around `1.0` per core can be normal under load;
- consistently above `1.0` indicates queueing/contention.

### 1.4 Why `MemAvailable` matters more than "free"

"Free" memory can be low and still healthy (cache usage).
Real pressure signal is low `MemAvailable` plus swap growth and latency symptoms.

### 1.5 What `vmstat 1 N` gives you

`vmstat` captures short-term behavior:

- `r` = runnable queue depth;
- `si/so` = swap in/out;
- `wa` = CPU waiting on IO.

### 1.6 Where `iostat` and `pidstat` help

- `iostat -xz` shows per-device latency/util behavior;
- `pidstat` identifies which processes produce current load.

### 1.7 Why snapshot + archive matters

In incidents, point-in-time capture is critical:

- compare before/after fix;
- preserve context before service restarts.

---

## 2. Command Priority (What to Learn First)

### Core (must know now)

- `uptime`
- `free -h`
- `ps -eo ... --sort=-%cpu`
- `ps -eo ... --sort=-%mem`
- `vmstat 1 5`
- `journalctl --since "-30 min" -p warning..alert`

### Optional (after core)

- `iostat -xz 1 5`
- `pidstat 1 5`
- `mpstat -P ALL 1 5`
- `top -b -n 1`

### Advanced (ops-grade)

- strict health-check for cron/CI signaling
- triage report with evidence files
- snapshot + tar.gz as incident artifact

---

## 3. Core Commands: What / Why / When

### `uptime`

- **What:** uptime plus 1/5/15 minute load.
- **Why:** immediate high-level baseline.
- **When:** first command in triage.

```bash
uptime
```

### `free -h`

- **What:** readable RAM/swap summary.
- **Why:** detect memory pressure and swap usage.
- **When:** immediately after load check.

```bash
free -h
```

### `ps ... --sort=-%cpu`

- **What:** top CPU consumers.
- **Why:** identify hot processes quickly.
- **When:** if load looks high.

```bash
ps -eo pid,ppid,comm,%cpu,%mem,state --sort=-%cpu | head -n 15
```

### `ps ... --sort=-%mem`

- **What:** top memory consumers.
- **Why:** identify memory-heavy workloads.
- **When:** if `MemAvailable` drops or swap grows.

```bash
ps -eo pid,ppid,comm,%cpu,%mem,state --sort=-%mem | head -n 15
```

### `vmstat 1 5`

- **What:** 1-second sampled CPU/memory/IO view.
- **Why:** shows dynamics, not a single static point.
- **When:** always after baseline `ps` checks.

```bash
vmstat 1 5
```

### `journalctl --since "-30 min" -p warning..alert`

- **What:** warnings/errors from last 30 minutes.
- **Why:** correlate system symptoms with metric spikes.
- **When:** alongside metric collection.

```bash
journalctl --since "-30 min" -p warning..alert --no-pager | tail -n 120
```

---

## 4. Optional Commands (After Core)

Optional is for deeper localization after core already signals pressure.

### 4.1 `iostat -xz 1 5`

- **What:** extended disk device statistics.
- **Why:** validate whether disk latency/util is bottleneck.
- **When:** when `vmstat wa` is elevated.

```bash
iostat -xz 1 5
```

### 4.2 `pidstat 1 5`

- **What:** sampled per-process activity.
- **Why:** catch short spikes that static `ps` may miss.
- **When:** intermittent lag/load events.

```bash
pidstat 1 5
```

### 4.3 `mpstat -P ALL 1 5`

- **What:** per-core CPU usage.
- **Why:** detect skewed load across cores.
- **When:** app latency exists but global CPU looks moderate.

```bash
mpstat -P ALL 1 5
```

### 4.4 `top -b -n 1`

- **What:** single batch dump of `top`.
- **Why:** easy evidence block for reports/tickets.
- **When:** when building triage artifacts.

```bash
top -b -n 1 | sed -n '1,40p'
```

### Practical Optional flow

1. If `vmstat` shows high `wa` -> run `iostat`.
2. If spikes are short -> run `pidstat`.
3. If one-core contention suspected -> run `mpstat -P ALL`.
4. Save outputs into one triage report.

---

## 5. Advanced Topics (Ops-Grade)

### 5.1 Threshold health-check in automation

`--strict` mode is for cron/CI signaling:

- exit code `0` = healthy;
- exit code `1` = pressure indicators found;
- easy integration with alerting hooks.

### 5.2 Triage report as handoff artifact

Extended report captures context for teammates:

- timing, host context, process tables, sampled metrics;
- reduces "what exactly did you run?" ambiguity.

### 5.3 Snapshot + archive workflow

Snapshot is your point-in-time evidence package:

- supports later re-analysis;
- attachable to incidents/tickets;
- protects context from loss after remediation steps.

---

## 6. Scripts in This Lesson

```bash
chmod +x lessons/14-performance-triage/scripts/*.sh

lessons/14-performance-triage/scripts/perf-health-check.sh
lessons/14-performance-triage/scripts/perf-triage.sh
lessons/14-performance-triage/scripts/perf-snapshot.sh
```

### `perf-health-check.sh`

**What it does:** fast load/memory/swap/iowait check + top process views.  
**Why:** detect obvious pressure in under a minute.  
**When to run:** at investigation start and in cron (`--strict`).

```bash
./lessons/14-performance-triage/scripts/perf-health-check.sh
./lessons/14-performance-triage/scripts/perf-health-check.sh --strict
```

### `perf-triage.sh`

**What it does:** extended triage report with time sampling (`vmstat`, optional `iostat/pidstat`).  
**Why:** produce reproducible evidence for analysis/handoff.  
**When to run:** when health-check fails or users report slowdowns.

```bash
./lessons/14-performance-triage/scripts/perf-triage.sh --seconds 8
./lessons/14-performance-triage/scripts/perf-triage.sh --seconds 8 --save-dir /tmp/lesson14-reports
./lessons/14-performance-triage/scripts/perf-triage.sh --strict --save-dir /tmp/lesson14-reports
```

### `perf-snapshot.sh`

**What it does:** collects diagnostics and packs them into `tar.gz`.  
**Why:** preserve incident evidence "as-is".  
**When to run:** before making changes, restart, or cleanup.

```bash
./lessons/14-performance-triage/scripts/perf-snapshot.sh
./lessons/14-performance-triage/scripts/perf-snapshot.sh --out-dir /tmp/lesson14-artifacts --seconds 8
```

---

## 7. Practice (Manual Flow)

### Step 1. Quick baseline

```bash
uptime
free -h
ps -eo pid,ppid,comm,%cpu,%mem,state --sort=-%cpu | head -n 12
vmstat 1 5
```

### Step 2. Go deeper (if needed)

```bash
iostat -xz 1 5
pidstat 1 5
journalctl --since "-30 min" -p warning..alert --no-pager | tail -n 120
```

### Step 3. Scripted triage + snapshot

```bash
./lessons/14-performance-triage/scripts/perf-triage.sh --seconds 8 --save-dir /tmp/lesson14-reports
./lessons/14-performance-triage/scripts/perf-snapshot.sh --out-dir /tmp/lesson14-artifacts --seconds 8
```

---

## 8. Troubleshooting

### "`iostat`/`pidstat` not found"

Install `sysstat`:

```bash
sudo apt-get update
sudo apt-get install -y sysstat
```

### "`perf-health-check --strict` exits non-zero"

Expected behavior. Strict mode intentionally returns failure when pressure indicators are detected.

### "Load is high but CPU is not 100%"

Check:

- `vmstat` (`r`, `wa`);
- `iostat` (disk bottleneck possibility);
- blocked task states in `ps`.

### "Snapshot misses `dmesg` details"

Expected when running without root privileges: the script keeps available data and writes an `INFO` note in `dmesg-err-warn.txt`.
Run snapshot with `sudo` if deeper kernel log context is required.

---

## 9. Lesson Summary

- **What I learned:** how to run layered performance triage across CPU/RAM/IO without diagnosing from a single metric.
- **What I practiced:** baseline checks (`uptime/free/ps/vmstat`), deeper sampling via `iostat/pidstat`, and scripted report/snapshot collection.
- **Advanced skills:** symptom-driven bottleneck localization using metrics and logs while separating root cause from side effects.
- **Operational focus:** evidence-first workflow (collect first, change later), reproducible reports, and safe artifact handoff.
- **Repo artifacts:** `lessons/14-performance-triage/scripts/`, `lessons/14-performance-triage/scripts/README.md`.
