# Boot/Recovery Scripts (Lesson 13)

This folder contains helper scripts for lesson 13 (boot diagnostics, failed-units triage, and recovery snapshots).

## Files

- `boot-health-check.sh`
  - quick checks for system run state, failed units, `findmnt --verify`, rootfs usage
  - `--strict` exits non-zero when warnings are found
- `boot-triage.sh`
  - focused boot triage report: `systemctl --failed`, `journalctl -b`, `dmesg`, `findmnt --verify`
  - supports `--boot`, `--since`, `--save-dir`, and `--strict`
- `recovery-snapshot.sh`
  - saves key config files and runtime diagnostics into timestamped snapshot directory
  - includes `dmesg`, `blkid`, and per-failed-unit dumps:
  - `systemctl cat <unit>`, `systemctl status <unit>`, `journalctl -b -u <unit>`
  - produces both snapshot folder and packed `tar.gz` archive at the end
  - helps keep rollback context before risky changes

## Requirements

- `bash`, `systemctl`, `journalctl`, `findmnt`, `df`, `lsblk`, `blkid`, `dmesg`, `tar`, `basename`
- optional `sudo` for richer `dmesg` access on hardened hosts

## Usage

From repo root:

```bash
chmod +x lessons/13-boot-recovery-troubleshooting/scripts/*.sh

lessons/13-boot-recovery-troubleshooting/scripts/boot-health-check.sh
lessons/13-boot-recovery-troubleshooting/scripts/boot-triage.sh --boot 0 --since "-2h"
lessons/13-boot-recovery-troubleshooting/scripts/recovery-snapshot.sh --out-dir /tmp
```

## Safety Notes

- Scripts are read-mostly and do not alter boot targets or kernel params.
- `recovery-snapshot.sh` copies config/diagnostic files; review output directory before sharing artifacts.
- Prefer running recovery-mode commands from local console/VM, not over remote SSH sessions.
