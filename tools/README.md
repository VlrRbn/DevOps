# Tools: Scripts Overview

This directory contains small operational helper scripts. Each script includes
its own header comment with purpose and usage.

## Index

- `apt-dry-upgrade.sh` — Run `apt update` and simulate an upgrade (dry-run).
- `backup-dir.sh` — Backup a directory to `~/backups` and keep last N archives.
- `backup-dir.v2.sh` — Backup with exclude/retention, locking, and validation.
- `capture-http.sh` — Capture TCP/80 traffic to a timestamped pcap.
- `devops-tail.sh` — Quick `systemctl status` + recent `journalctl` for a unit.
- `devops-tail.v2.sh` — Flexible journal viewer with since/lines/follow/priority.
- `dns-query.sh` — Query common DNS records (A/AAAA/CNAME/NS/TXT).
- `hello.sh` — Emit a timestamped log line to journald.
- `imds-test.sh` — Test IMDSv1 (fail) vs IMDSv2 (success) on EC2.
- `log-grep.sh` — Grep a pattern in a file or recursively in a directory.
- `log-grep.v2.sh` — Grep files or journal with unit/tag filters.
- `log-nginx-report.sh` — Summarize nginx access logs (codes, paths, IPs).
- `log-ssh-fail-report.sh` — Report top SSH failed login IPs.
- `log-ssh-fail-report.v2.sh` — SSH failed login report with filters/time range.
- `mkshare.sh` — Create a shared group directory with SGID/ACLs.
- `net-ports.sh` — List TCP ports with ss and optional filters.
- `netns-nft.apply.sh` — Apply nftables NAT rules for a netns lab.
- `nft-save-restore.sh` — Save/restore/validate/show/diff nftables rules.
- `nginx-bluegreen-deploy.sh` — Switch to a *_v2 nginx site and reload safely.
- `nginx-reload-safe.sh` — Validate nginx config and reload if OK.
- `pkg-snapshot.sh` — Snapshot installed packages to lists.
- `pkg-restore.sh` — Restore package selections from `packages.list`.
- `rename-ext.sh` — Rename file extensions (non-recursive).
- `rename-ext.v2.sh` — Rename file extensions recursively with dry-run/verbose.
- `ssm-forward.sh` — Start SSM port-forwarding to a `Role=web` instance.
- `_template.sh` — Shell script template with strict mode and trap.

## Notes

- Many scripts use `sudo`; run them as a user with sudo privileges.
- Some scripts assume Ubuntu (e.g., apt-based or journald-based).
- For AWS-related scripts, ensure `aws` CLI is configured and SSM Session Manager plugin is installed.
