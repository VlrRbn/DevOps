# Text Processing Scripts (Lesson 08)

This folder contains practical scripting artifacts (`grep`, `sed`, `awk`) used in lesson 08.

## Files

- `log-ssh-fail-report.sh`
  - top SSH failed-login IPs (journal/auth)
- `log-ssh-fail-report.v2.sh`
  - same with `--source`, `--since`, `--top`, `--all`
- `log-grep.sh`
  - grep helper for file or directory target
- `log-grep.v2.sh`
  - grep helper for file/dir/journal with `--unit`, `--tag`, `--sshd-only`
- `log-nginx-report.sh`
  - nginx access summary (total, error rate, status counts, top paths, unique IPs)

## Requirements and Setup

- `bash`
- `grep`, `sed`, `awk`
- `journalctl` (for journal mode)

```bash
chmod +x lessons/08-text-processing-grep-sed-awk/scripts/*.sh
```

## Usage

From repo root:

```bash
lessons/08-text-processing-grep-sed-awk/scripts/log-ssh-fail-report.sh
lessons/08-text-processing-grep-sed-awk/scripts/log-ssh-fail-report.v2.sh --source auth --all --top 10

lessons/08-text-processing-grep-sed-awk/scripts/log-grep.sh "Failed password|Accepted password" /var/log/auth.log
lessons/08-text-processing-grep-sed-awk/scripts/log-grep.v2.sh "Failed password" journal --tag sshd

lessons/08-text-processing-grep-sed-awk/scripts/log-nginx-report.sh
```

## Safety Notes

- `auth.log` commands may require `sudo`.
- On systems without `/var/log/auth.log`, use journal mode.
- `log-nginx-report.sh` defaults to:
  `-/var/log/nginx/access.log`.
