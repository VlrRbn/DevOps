# lesson_07

# Bash Scripting: Safe Patterns and Practical Automation

**Date:** 2025-08-27  
**Topic:** Bash safety patterns, argument parsing, file automation, backups, and journald helpers  
**Daily goal:** Write reliable Bash scripts that are safe by default and useful for daily ops tasks.
**Bridge:** [05-07 Operations Bridge](../00-foundations-bridge/05-07-operations-bridge.md) for missing practical gaps after lessons 5-7.

---

## 1. Core Concepts

### 1.1 Script safety baseline

A safe Bash script should start with:

- strict mode (`set -Eeuo pipefail`)
- safe splitting (`IFS=$'\n\t'`)
- error visibility (`trap ... ERR`)

This catches silent failures early.

### 1.2 Input and output discipline

For predictable behavior:

- validate input arguments
- quote variables (`"$var"`)
- use arrays for command composition
- print explicit success/error messages

### 1.3 Idempotence and dry-run mindset

For operational scripts, prefer behavior that is:

- repeatable (multiple runs do not break state)
- previewable (`-n` / `--dry-run` where possible)
- explicit about destructive actions

### 1.4 Why ShellCheck matters

`shellcheck` catches common Bash issues before runtime:

- unquoted variables
- brittle loops over filenames
- hidden pipeline errors
- unsafe expansion patterns

### 1.5 What’s responsible for what?

- **Core:** minimum commands to write and verify simple scripts safely.
- **Optional:** productivity and robustness upgrades for real-world file paths/logs.
- **Advanced:** operations-grade patterns (locking, rotation, follow mode, better CLI UX).

### 1.6 Mini shell syntax cheat sheet (for this lesson)

If a script line looks hard to read, it is usually shell syntax:

- `$var` is variable value.
- `${var}` is the same, but safer near adjacent text (`"${base}_$ts"`).
- `$(command)` inserts command output.
- `printf '%s\n' "$name"` means: `%s` is string placeholder, `\n` is newline.
- `2>/dev/null` hides stderr from a command.
- `cmd || true` keeps script flow where a failure is expected.
- `cmd1 && cmd2` runs `cmd2` only if `cmd1` succeeded.
- `--` marks end of options; next tokens are positional args (useful for weird filenames).

---

## 2. Command Priority (What to Learn First)

### Core (must know now)

- `bash -n <script.sh>`
- `shellcheck <script.sh>`
- `chmod +x <script.sh>`
- `./<script.sh> --help`
- `set -Eeuo pipefail` pattern
- basic `getopts` usage

### Optional (useful after core)

- `find ... -print0` + `read -r -d ''`
- `xargs -0`
- `tar -C ... -czf ...`
- `journalctl -u <unit> --since ... -n ...`
- `systemctl status <unit> --no-pager`

### Advanced (ops-ready scripting)

- `flock` for single-instance execution
- `logger -t <tag>` for syslog/journal trail
- command arrays for safe dynamic command build
- script flags for dry-run/verbose/follow/priority
- backup retention and artifact validation

---

## 3. Core Commands and Patterns: What / Why / When

### `bash -n <script.sh>`

- **What:** syntax check without execution.
- **Why:** catches parse errors immediately.
- **When:** every edit before running script.

```bash
bash -n lessons/07-bash-scripting-automation/scripts/rename-ext.sh
```

### `shellcheck <script.sh>`

- **What:** static analysis for shell scripts.
- **Why:** finds quoting/splitting/logic pitfalls early.
- **When:** before commit and before production usage.

```bash
shellcheck lessons/07-bash-scripting-automation/scripts/backup-dir.sh
```

### `chmod +x <script.sh>` + direct execution

- **What:** mark script executable and run directly.
- **Why:** standard usage flow for reusable helpers.
- **When:** after creating/updating script.

```bash
chmod +x lessons/07-bash-scripting-automation/scripts/*.sh
./lessons/07-bash-scripting-automation/scripts/rename-ext.sh --help
```

### Safe template baseline

- **What:** minimal template with strict mode, IFS, and ERR trap.
- **Why:** prevents silent and hard-to-debug failures.
- **When:** starting any new operational script.

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "ERR:$? at ${BASH_SOURCE[0]}:${LINENO}" >&2' ERR
```

### Basic `getopts` for flags

- **What:** parse script options (`-n`, `-v`, etc.) reliably.
- **Why:** cleaner CLI and consistent behavior.
- **When:** script has optional behavior flags.

```bash
dry=0
while getopts ":nv" opt; do
  case "$opt" in
    n) dry=1 ;;
    v) verbose=1 ;;
    *) echo "Usage..."; exit 1 ;;
  esac
done
shift $((OPTIND-1))
```

---

## 4. Optional Commands and Why They Matter

### `find ... -print0` + `read -r -d ''`

- **What:** NUL-delimited safe file iteration.
- **Why:** handles spaces/newlines in filenames safely.
- **When:** recursive operations on arbitrary user files.

```bash
find "$dir" -type f -name "*.txt" -print0 |
while IFS= read -r -d '' f; do
  echo "$f"
done
```

### `xargs -0`

- **What:** consume NUL-delimited input safely.
- **Why:** robust batch operations without word-splitting bugs.
- **When:** cleanup/rotation pipelines.

```bash
find "$out" -type f -name '*.tar.gz' -print0 | xargs -0 -r rm -f
```

Anti-pattern to avoid:

```bash
for f in $(find "$dir" -type f); do
  echo "$f"
done
```

Why this is brittle:

- breaks on spaces in filenames
- breaks on newlines in filenames

Preferred pattern in this lesson: `find -print0` with `read -d ''` or `xargs -0`.

### `tar -C ... -czf ...`

- **What:** create compressed archive from controlled base dir.
- **Why:** avoids embedding absolute paths and keeps archive predictable.
- **When:** backups, artifacts, migration packs.

```bash
tar -C "$(dirname -- "$dir")" -czf "$tarball" "$(basename -- "$dir")"
```

### `systemctl status` + `journalctl -u`

- **What:** unit status snapshot and related logs.
- **Why:** fast troubleshooting context.
- **When:** validating service behavior after script changes/deploys.

```bash
systemctl status cron --no-pager | sed -n '1,12p'
journalctl -u cron --since "15 min ago" -n 50 --no-pager
```

---

## 5. Advanced Topics (Ops-Grade Patterns)

These patterns directly affect reliability and operational safety:

- avoiding concurrent writes with locks
- preserving forensic trail via journald/syslog
- adding CLI modes (`--dry-run`, `--follow`) to avoid risky blind actions

### 5.1 Single-instance execution with `flock`

- **What:** lock script execution per target resource.
- **Why:** prevent overlapping backup runs and corrupted artifacts.
- **When:** scheduled scripts (cron/systemd timer) and shared resources.

Pattern:

```bash
lock="/tmp/backup-$base.lock"
{
  flock -n 9 || { echo "Another run in progress" >&2; exit 1; }
  # critical section
} 9> "$lock"
```

### 5.2 Audit trail via `logger`

- **What:** write structured message to system logs.
- **Why:** scripts become observable from journal/syslog.
- **When:** backup, deploy, rotation, maintenance scripts.

```bash
logger -t backup "Created $tarball"
```

### 5.3 Command arrays for safe dynamic calls

- **What:** build command as Bash array.
- **Why:** avoids quoting bugs when optional args are conditional.
- **When:** scripts with optional flags/filters.

```bash
cmd=(tar -C "$base_dir" -czf "$tarball")
[[ -n "$exclude" ]] && cmd+=("--exclude=$exclude")
cmd+=("$base")
"${cmd[@]}"
```

### 5.4 Archive validation before rotate/delete

- **What:** verify new archive before deleting old backups.
- **Why:** avoids rotation after broken backup generation.
- **When:** any retention-based backup script.

```bash
tar -tzf "$tarball" >/dev/null
```

### 5.5 Unattended log helper flags (`-s/-n/-f/-p`)

- **What:** configurable log queries by time, lines, follow mode, priority.
- **Why:** one helper script replaces repetitive manual journalctl typing.
- **When:** incident triage and quick service checks.

Example:

```bash
./lessons/07-bash-scripting-automation/scripts/devops-tail.v2.sh cron -s "1 hour ago" -n 200 -p warning
```

---

## 6. Scripts in This Lesson

This lesson includes ready-to-run artifacts in:

- `lessons/07-bash-scripting-automation/scripts/`

Install execution bit once:

```bash
chmod +x lessons/07-bash-scripting-automation/scripts/*.sh
```

---

## 7. Mini-lab (Core Path)

### Goal

Build confidence in safe script workflow: syntax -> lint -> run -> verify.

### Steps

1. Run syntax and lint checks.
2. Test simple extension rename in a temp directory.
3. Create one backup archive.
4. Use log helper for a known unit.

```bash
bash -n lessons/07-bash-scripting-automation/scripts/rename-ext.sh
shellcheck lessons/07-bash-scripting-automation/scripts/rename-ext.sh

mkdir -p /tmp/lab7 && : > /tmp/lab7/a.txt && : > /tmp/lab7/b.txt
./lessons/07-bash-scripting-automation/scripts/rename-ext.sh txt md /tmp/lab7
ls -1 /tmp/lab7

./lessons/07-bash-scripting-automation/scripts/backup-dir.sh /tmp/lab7 --keep 3
ls -1t "$HOME"/backups/lab7_* | head -n 3

./lessons/07-bash-scripting-automation/scripts/devops-tail.sh cron --since "15 min ago" || true
```

Validation checklist:

- script passes syntax and static checks
- rename works on expected files
- backup archive is created
- service helper shows status + logs

---

## 8. Extended Lab (Optional + Advanced)

### 8.1 Recursive rename with dry-run/verbose

```bash
mkdir -p "/tmp/lab7 deep/path one"
: > "/tmp/lab7 deep/path one/file one.txt"
: > "/tmp/lab7 deep/path one/file two.txt"

./lessons/07-bash-scripting-automation/scripts/rename-ext.v2.sh -nv txt md "/tmp/lab7 deep"
./lessons/07-bash-scripting-automation/scripts/rename-ext.v2.sh -v txt md "/tmp/lab7 deep"
```

### 8.2 Backup lock and retention behavior

```bash
./lessons/07-bash-scripting-automation/scripts/backup-dir.v2.sh /tmp/lab7 --keep 2
./lessons/07-bash-scripting-automation/scripts/backup-dir.v2.sh /tmp/lab7 --keep 2 --exclude 'lab7/*.md'
ls -1t "$HOME"/backups/lab7_* | head -n 5
```

### 8.3 Flexible journal helper usage

```bash
./lessons/07-bash-scripting-automation/scripts/devops-tail.v2.sh cron -s "1 hour ago" -n 100 || true
./lessons/07-bash-scripting-automation/scripts/devops-tail.v2.sh cron -f || true
```

Stop follow mode with `Ctrl+C`.

### 8.4 Suggested self-check

- run each script with wrong args and verify usage/error quality
- run each script on paths containing spaces
- ensure destructive commands support preview mode where applicable

---

## 9. Cleanup

```bash
rm -rf /tmp/lab7 "/tmp/lab7 deep"
```

---

## 10. Lesson Summary

- **What I learned:** safe Bash baseline, argument parsing, and robust file/log automation patterns.
- **What I practiced:** syntax/lint flow, extension rename, archive rotation, and journal helper scripts.
- **Advanced skills:** lock-based serialization, syslog tracing, command arrays, and safer retention logic.
- **Operational focus:** avoid silent failures, support preview-first behavior, and keep scripts observable.
- **Repo artifacts:** `lessons/07-bash-scripting-automation/scripts/`.
