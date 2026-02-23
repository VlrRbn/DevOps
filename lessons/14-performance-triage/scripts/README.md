# Performance Triage Scripts (Lesson 14)

This folder contains helper scripts for lesson 14 (Linux performance triage and evidence collection).

## Files

- `perf-health-check.sh`
  - quick load/memory/swap/iowait checks + top CPU/MEM process views
  - supports `--strict` (non-zero exit on warning thresholds)
- `perf-triage.sh`
  - extended triage report: uptime/load, memory, top processes, `vmstat`
  - optional `iostat`/`pidstat` blocks when tools are available
  - supports `--seconds`, `--save-dir`, `--strict`
- `perf-snapshot.sh`
  - captures point-in-time performance/system artifacts into timestamped folder
  - packages snapshot as `.tar.gz` for handoff/incidents

## Requirements

- `bash`, `awk`, `nproc`, `free`, `ps`, `uptime`, `vmstat`, `journalctl`, `tar`
- optional: `iostat`, `pidstat`, `mpstat` (from `sysstat`)
- optional: run with `sudo` (or as root) for richer `dmesg` capture in snapshot mode

## Usage

From repo root:

```bash
chmod +x lessons/14-performance-triage/scripts/*.sh

lessons/14-performance-triage/scripts/perf-health-check.sh
lessons/14-performance-triage/scripts/perf-health-check.sh --strict

lessons/14-performance-triage/scripts/perf-triage.sh --seconds 8 --save-dir /tmp/lesson14-reports
lessons/14-performance-triage/scripts/perf-triage.sh --strict --save-dir /tmp/lesson14-reports

lessons/14-performance-triage/scripts/perf-snapshot.sh --out-dir /tmp/lesson14-artifacts --seconds 8
```

## Expected Outputs

- `perf-triage.sh --save-dir ...`
  - creates `perf-triage_YYYYmmdd_HHMMSS.txt`
- `perf-snapshot.sh --out-dir ...`
  - creates `perf-snapshot_YYYYmmdd_HHMMSS/`
  - creates `perf-snapshot_YYYYmmdd_HHMMSS.tar.gz`

## Safety Notes

- Scripts are read-mostly and do not tune kernel/sysctl automatically.
- `--strict` is intended for automation signaling (cron/CI), not as a replacement for human diagnosis.
- Snapshot artifacts may include host/process metadata; review before sharing outside your environment.
