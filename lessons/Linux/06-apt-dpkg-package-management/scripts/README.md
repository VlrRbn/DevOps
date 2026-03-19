# Package Management Scripts (Lesson 06)

This folder contains helper scripts for lesson 06 package-management labs.

## Files

- `apt-dry-upgrade.sh`
  - refreshes index and simulates upgrade
  - use `--full` to simulate `full-upgrade`
- `pkg-snapshot.sh`
  - creates package snapshot artifacts (`packages.list`, `packages_table.txt`)
- `pkg-restore.sh`
  - restores selections from `packages.list`
  - default mode: simulation
  - `--apply`: real restore
- `unattended-dry-run.sh`
  - checks apt timers, runs unattended-upgrade dry-run, and shows logs

## Requirements

- `bash`
- `sudo`
- apt tools (`apt`, `apt-get`, `apt-cache`, `dpkg`)
- `unattended-upgrade` command for `unattended-dry-run.sh`

## Usage

From repo root:

```bash
lessons/06-apt-dpkg-package-management/scripts/apt-dry-upgrade.sh
lessons/06-apt-dpkg-package-management/scripts/apt-dry-upgrade.sh --full

lessons/06-apt-dpkg-package-management/scripts/pkg-snapshot.sh ./pkg-state
lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh ./pkg-state/packages.list
lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh --apply ./pkg-state/packages.list

lessons/06-apt-dpkg-package-management/scripts/unattended-dry-run.sh
```

## Safety Notes

- `pkg-restore.sh` defaults to simulation. Use `--apply` only when you intentionally want real changes.
- restore operations can install/remove packages according to the selection file.
- run restore on the intended host only, with reviewed input files.
