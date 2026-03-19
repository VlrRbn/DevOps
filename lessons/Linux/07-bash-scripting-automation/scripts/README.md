# Bash Automation Scripts (Lesson 07)

This folder contains practical scripting artifacts used in lesson 07.

## Files

- `script-template.sh`
  - strict-mode Bash template with ERR trap and safe IFS
- `rename-ext.sh`
  - non-recursive extension rename
- `rename-ext.v2.sh`
  - recursive rename with `-n` (dry-run) and `-v` (verbose)
- `backup-dir.sh`
  - timestamped tar.gz backup with retention
- `backup-dir.v2.sh`
  - backup with lock (`flock`), optional exclude, archive validation, and syslog logging
- `devops-tail.sh`
  - status + journal helper for one unit
- `devops-tail.v2.sh`
  - flexible helper with `-s`, `-n`, `-f`, `-p`

## Requirements

- `bash`
- `sudo` (for some operations)
- `shellcheck` (recommended for linting)
- `systemd` tools for journal helpers (`systemctl`, `journalctl`)
- `flock` and `logger` (typically available on Ubuntu server/desktop)

## Usage

From repo root:

```bash
chmod +x lessons/07-bash-scripting-automation/scripts/*.sh

lessons/07-bash-scripting-automation/scripts/rename-ext.sh txt md /tmp/lab7
lessons/07-bash-scripting-automation/scripts/rename-ext.v2.sh -nv txt md /tmp/lab7

lessons/07-bash-scripting-automation/scripts/backup-dir.sh /tmp/lab7 --keep 3
lessons/07-bash-scripting-automation/scripts/backup-dir.v2.sh /tmp/lab7 --keep 2 --exclude 'lab7/*.md'

lessons/07-bash-scripting-automation/scripts/devops-tail.sh cron --since "15 min ago"
lessons/07-bash-scripting-automation/scripts/devops-tail.v2.sh cron -s "1 hour ago" -n 100
```

## Safety Notes

- `rename-ext.v2.sh` supports dry-run (`-n`): use it before real rename.
- backup scripts can remove old archives due to retention logic; verify keep count.
- `devops-tail.v2.sh -f` runs in follow mode until interrupted with `Ctrl+C`.
