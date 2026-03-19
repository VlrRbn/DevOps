# Linux Capstone Scripts (Lesson 15)

This folder contains helper scripts for the final Linux capstone lesson.

## Files

- `capstone-health-check.sh`
  - quick Linux health gate: system state, load/memory, disk pressure, default route, DNS check
  - optional egress HTTPS check via `curl` (`OK`/`FAIL`/`SKIPPED`)
  - supports `--strict` (non-zero exit when warnings are found)
  - supports `--json` for machine-readable output
- `capstone-triage.sh`
  - extended triage report: systemd state, resources, process top, network, storage, journal, optional dmesg
  - includes failed unit names (not only count), plus egress HTTPS status
  - supports `--seconds`, `--since`, `--save-dir`, `--strict`, `--json`
- `capstone-snapshot.sh`
  - captures incident-ready evidence bundle into timestamped folder
  - packs everything into `.tar.gz` for handoff
  - supports `--out-dir`, `--since`, `--seconds`

## Requirements

- `bash`, `awk`, `free`, `df`, `uptime`, `nproc`, `vmstat`, `ip`, `ss`, `lsblk`, `findmnt`, `journalctl`, `tar`
- optional: `systemctl` for failed-unit and run-state sections
- optional: `curl` for egress HTTPS check (`https://example.com`)
- optional: `iostat`, `pidstat` (from `sysstat`) for deeper process/disk sampling
- optional: run with `sudo` for richer `dmesg` capture

## Usage

From repo root:

```bash
chmod +x lessons/15-linux-capstone-incident-runbook/scripts/*.sh

lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh
lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh --strict
lessons/15-linux-capstone-incident-runbook/scripts/capstone-health-check.sh --json

lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --seconds 8 --since "-4h" --save-dir /tmp/lesson15-reports
lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --strict --save-dir /tmp/lesson15-reports
lessons/15-linux-capstone-incident-runbook/scripts/capstone-triage.sh --seconds 8 --json --save-dir /tmp/lesson15-reports

lessons/15-linux-capstone-incident-runbook/scripts/capstone-snapshot.sh --out-dir /tmp/lesson15-artifacts --since "-4h" --seconds 8
```

## Expected Outputs

- `capstone-triage.sh --save-dir ...`
  - creates `capstone-triage_YYYYmmdd_HHMMSS.txt` (default mode)
  - creates `capstone-triage_YYYYmmdd_HHMMSS.json` (with `--json`)
- `capstone-snapshot.sh --out-dir ...`
  - creates `capstone-snapshot_YYYYmmdd_HHMMSS/`
  - creates `capstone-snapshot_YYYYmmdd_HHMMSS.tar.gz`

## Safety Notes

- Scripts are diagnostics-first and avoid destructive actions.
- `--strict` is intended for automation signaling (cron/CI), not as a replacement for human diagnosis.
- Snapshot artifacts may include host/process metadata; review before sharing outside your environment.
