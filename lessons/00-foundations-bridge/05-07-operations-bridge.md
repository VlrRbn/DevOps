# 05-07 Operations Bridge (After Lessons 5-7)

**Purpose:** keep all detailed explanations in one place, but sort them by lessons 5, 6, and 7.

**How to read this file:**

- start with the lesson-specific block you are currently revising;
- then use FAQ/checklist/deep-lab sections.

---

## Lesson 05: systemd, journald, service diagnostics

### Systemd + Journald

#### What a unit is

A unit is a systemd-managed object:

- service
- timer
- socket
- etc.

#### Basic triage flow

1. `systemctl status <unit>`
2. `journalctl -u <unit> ...`
3. add time/priority filters as needed

#### Why `--no-pager`

Output goes directly to terminal/script (no interactive pager).

#### Why `sed -n '1,12p'`

Get short status summary instead of full long output.

#### Priority filtering

```bash
journalctl -u cron -p warning --since "1 hour ago"
```

Meaning:

- only `cron` unit logs
- only warning and above
- limited time range

#### Follow mode

```bash
journalctl -u cron -f
```

Live stream until `Ctrl+C`.

---


---

## Lesson 06: APT/DPKG, restore, unattended-upgrades

### APT/DPKG: Relation to Lesson 6 and Bridge

#### Tool responsibilities

- `apt` -> interactive convenience
- `apt-get` -> stable scripting behavior
- `apt-cache` -> metadata queries
- `dpkg` -> local package/database state

#### What Candidate means

In `apt-cache policy`:

- `Installed` = current version
- `Candidate` = version apt would pick now

#### What `500` means

`500` is Pin-Priority for repository source. It is not percentage/quality.

Quick map:

- `100` -> local installed status
- `500` -> normal repository
- `990` -> target release preference
- `1001+` -> forced preference

#### Hold lifecycle

```bash
sudo apt-mark hold htop
apt-mark showhold
sudo apt-mark unhold htop
```

Use to temporarily freeze one package.

Risk: forgotten holds cause long-term patch lag.

#### Why simulation-first

```bash
sudo apt-get -s upgrade
sudo apt-get -s full-upgrade
```

This previews impact before real change.

---


### Restore via Selections: What and Why

#### Snapshot

```bash
dpkg --get-selections > packages.list
dpkg -l > packages_table.txt
```

- `packages.list` -> machine-usable restore input
- `packages_table.txt` -> human-readable inventory snapshot

#### Simulate restore

```bash
sudo dpkg --set-selections < packages.list
sudo apt-get -s dselect-upgrade
```

#### Apply restore

```bash
sudo apt-get -y dselect-upgrade
```

Do this only after reading simulation output.

---


### Unattended-Upgrades: Why, Where, and Caution

#### What it is

Auto-applies updates (often security updates) without manual daily action.

#### Where useful

- servers requiring regular security patching
- environments with limited daily manual ops time

#### Where caution is needed

- strict change-management production
- systems where every update must pass staging approval

#### Low-risk validation

```bash
sudo unattended-upgrade --dry-run --debug | sed -n '1,80p'
systemctl list-timers --all | grep -E 'apt-daily|apt-daily-upgrade'
journalctl -u apt-daily-upgrade.service -n 50 --no-pager
```

---


---

## Lesson 07: Bash scripting and safe automation

### How to Read Commands (Most Important Section)

This section is intentionally first. Most confusion is not "Linux magic" - it is command syntax.

#### What placeholders and symbols mean

When you see:

- `<name>` -> placeholder, replace with your own value
- `[--flag]` -> optional argument
- `A | B` -> either `A` or `B`
- `...` -> continue in the same pattern

Example:

```bash
script.sh <src_ext> <dst_ext> <dir> [--dry-run]
```

Meaning:

- `src_ext`, `dst_ext`, `dir` are required
- `--dry-run` is optional

#### Single vs double quotes

- `'...'` -> almost no substitution inside
- `"..."` -> variables like `$name` are expanded

Example:

```bash
name="world"
echo '$name'
echo "$name"
```

Expected:

- first line prints literal `$name`
- second line prints `world`

#### `$name`, `${name}`, `$(...)`

- `$name` -> variable value
- `${name}` -> same, but safer next to text
- `$(command)` -> command substitution (insert command output)

Example:

```bash
base="backup"
echo "${base}_$(date +%Y%m%d)"
```

#### What `%s` and `\n` mean in `printf`

Example:

```bash
name="a b.txt"
printf '%s\n' "$name"
```

Breakdown:

- `printf` prints text using a format string
- `%s` = insert a string
- `\n` = newline
- full command means: print `name` and move to next line

Why not `echo`:

- `printf` behavior is more predictable in scripts

#### `2>/dev/null`, `|| true`, `&&`

- `2>/dev/null` -> send stderr to null sink
- `cmd || true` -> do not fail whole flow if `cmd` fails
- `cmd1 && cmd2` -> run `cmd2` only if `cmd1` succeeds

#### What `--` means

`--` usually means "end of options, next tokens are positional args".

Useful when filename starts with `-`.

```bash
rm -- -strange-file
```

---


### Script Execution Context and Interpreter

#### Shebang: where it comes from and why

First line of script:

```bash
#!/usr/bin/env bash
```

This tells Linux which interpreter to use.

Common variants:

- `#!/bin/bash` -> fixed absolute path
- `#!/usr/bin/env bash` -> resolve `bash` via `PATH`

Why `env` is common:

- better portability
- less hardcoded path coupling

#### Three run modes and why they differ

1. `bash script.sh`
2. `./script.sh`
3. `script.sh`

Difference:

- `bash script.sh` -> explicit interpreter, execute bit not required
- `./script.sh` -> execute file from current directory, execute bit required
- `script.sh` -> searched in `PATH`; often not found

#### "File exists but does not run"

Check in this order:

```bash
ls -l script.sh
head -n 1 script.sh
file script.sh
```

Look for:

- execute bit present
- valid shebang
- no CRLF line endings

#### Mini-practice

```bash
mkdir -p ~/bridge57/context && cd ~/bridge57/context
cat > hello.sh <<'EOF'
#!/usr/bin/env bash
echo "hello"
EOF

bash hello.sh
chmod +x hello.sh
./hello.sh
```

If all is correct, both runs print `hello`.

---


### Exit Codes and Execution Flow

#### Exit code in plain words

Every command ends with a number:

- `0` -> success
- non-zero -> error or special status

Read last status via `$?`.

```bash
true; echo "$?"
false; echo "$?"
```

#### `&&` and `||` on real examples

```bash
mkdir -p /tmp/demo && echo "dir ok"
ls /not-exists || echo "fallback"
```

Meaning:

- second line: `ls` fails, right side after `||` runs

#### Common trap

`grep` returns `1` when no matches found. With `set -e`, that can stop the script.

That is why you may see:

```bash
grep "needle" file || true
```

Meaning: "no match is acceptable here".

#### `set -e` is useful, not magical

Edge cases exist in:

- `if` conditions
- pipelines
- complex chains

Reliable scripts combine:

- `set -Eeuo pipefail`
- explicit expected-failure handling
- focused `|| true` only where intentional

---


### Strict Mode: What Each Flag Actually Does

#### `set -Eeuo pipefail`

- `-e` -> exit on command failure
- `-u` -> fail on unset variable usage
- `pipefail` -> pipeline fails if any stage fails
- `-E` -> ERR trap propagates into functions/subshells

#### `IFS=$'\n\t'`

`IFS` controls shell word splitting.

Default includes spaces, which can break paths like `"file one.txt"`.

`IFS=$'\n\t'` avoids split-by-space behavior.

#### ERR trap

```bash
trap 'echo "ERR:$? at ${BASH_SOURCE[0]}:${LINENO}" >&2' ERR
```

You get:

- exit code
- file name
- line number
- stderr output

#### EXIT trap for cleanup

```bash
tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT
```

Even on failure, cleanup still runs.

---


### Quoting and Expansion Without Pain

#### Core rule

If variable may contain spaces, quote it:

```bash
rm -f "$file"
```

#### `echo` vs `printf`

For scripts, `printf` is usually safer:

```bash
name="a b.txt"
printf '%s\n' "$name"
```

#### `${f%"$src"}` in rename scripts

Example:

```bash
f="/tmp/a.txt"
src=".txt"
dst=".md"
new="${f%"$src"}$dst"
```

What happens:

- remove suffix `.txt`
- append `.md`
- result `/tmp/a.md`

#### `${var:-default}`

```bash
echo "${APP_ENV:-dev}"
```

If `APP_ENV` is unset/empty, fallback to `dev`.

---


### Command Arrays: Foundation of Safe Dynamic Commands

#### Why command-as-string is risky

Bad pattern:

```bash
cmd="tar -czf $tarball $dir"
$cmd
```

Problems:

- shell re-splits words
- breaks on spaces/special characters

#### Safe pattern

```bash
cmd=(tar -czf "$tarball" "$dir")
"${cmd[@]}"
```

Benefits:

- argument boundaries preserved
- safer for paths with spaces
- easier optional flag handling

#### Conditional argument injection

```bash
[[ -n "$exclude" ]] && cmd+=("--exclude=$exclude")
```

If `exclude` is empty, nothing is appended.

---

### `getopts`: How to Read and Write Option Parsing

#### What `getopts` does

`getopts` parses short CLI flags (`-n`, `-v`, `-f value`) inside shell scripts.

It is better than ad-hoc parsing because:

- control flow is cleaner;
- fewer argument-order bugs;
- usage/error handling is consistent.

#### Baseline pattern

```bash
dry=0
verbose=0
since=""

while getopts ":nvs:" opt; do
  case "$opt" in
    n) dry=1 ;;
    v) verbose=1 ;;
    s) since="$OPTARG" ;;
    \?) echo "Unknown option: -$OPTARG" >&2; exit 1 ;;
    :) echo "Option -$OPTARG requires a value" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))
```

How to read `:nvs:`:

- `n` and `v` are flags without values;
- `s:` means `-s` requires a value;
- leading `:` allows explicit handling of “missing value” cases.

#### Common mistakes

- forgetting `shift $((OPTIND-1))`, which breaks positional args;
- not handling missing value for value-required options;
- mixing `getopts` with manual parsing without a clear scheme.

---



### Safe File Traversal and Bulk Operations

#### Why `for f in $(find ...)` is dangerous

Because:

- spaces split words
- newlines split words

#### Robust pattern

```bash
find "$dir" -type f -print0 |
  while IFS= read -r -d '' f; do
    printf '%s\n' "$f"
  done
```

Why it works:

- `-print0` emits NUL-separated items
- `read -d ''` reads until NUL
- `IFS=` + `-r` preserves raw names

#### When to use `xargs -0`

```bash
find "$dir" -type f -name '*.tmp' -print0 | xargs -0 -r rm -f
```

- `-0` = NUL input
- `-r` = do nothing if no input

---


### Backup Logic from Lesson 07: Full Breakdown

#### End-to-end flow

1. validate args
2. build target archive path
3. create archive with `tar`
4. validate archive integrity
5. rotate old backups
6. log event

#### Why `tar -C` matters

```bash
tar -C "$(dirname -- "$dir")" -czf "$tarball" "$(basename -- "$dir")"
```

This keeps internal archive paths relative and restore-friendly.

#### Validate before retention cleanup

```bash
tar -tzf "$tarball" >/dev/null
```

Meaning: do not delete old backups if new archive is broken.

#### Retention (`keep N`)

Typical flow:

- list archives
- sort by time
- skip newest N
- remove tail

#### Exclude patterns (`--exclude`)

Use excludes for:

- cache
- temp files
- huge irrelevant paths

Always test pattern behavior on sample data first.

---

### `flock`: Protection Against Concurrent Runs

#### Why this matters

If a script runs via `cron`/`timer`, overlapping runs can corrupt output (especially backup/rotation flows).

`flock` enforces single-instance behavior.

#### Basic pattern

```bash
lock="/tmp/backup-${base}.lock"
{
  flock -n 9 || { echo "Another run is in progress" >&2; exit 1; }
  # critical section
  ./do-work.sh
} 9>"$lock"
```

Key details:

- `-n` means fail fast instead of waiting forever;
- `9>"$lock"` opens lock file on FD 9;
- if lock is busy, script exits cleanly.

#### Quick runtime check

Run the script twice. Second run should fail fast with a clear message.

---

### `logger` and Script Observability

#### Why ops scripts need this

Terminal `echo` is temporary.  
`logger` sends events to system log, retrievable later via `journalctl`.

#### Minimal pattern

```bash
logger -t backup "Created archive: $tarball"
logger -t backup "Rotation completed (keep=$keep)"
```

Validation:

```bash
journalctl -t backup -n 50 --no-pager
```

#### Practical rule

- log key milestones (start, success, failure);
- include context (file/unit/count/duration);
- avoid logging sensitive data.

---




---

## General: FAQ, checklist, deep mini-lab, and next steps

### Common Questions (FAQ)

#### Why does `./script.sh` work but `script.sh` does not?

Because `script.sh` is searched in `PATH`; current directory is usually not included.

#### Why does `echo` behave inconsistently?

`echo` handling of escapes can vary by shell/context. `printf` is usually safer in scripts.

#### Why did `grep` fail if it simply found nothing?

Because "no match" is exit code `1` for `grep`.

#### Why did script remove wrong files?

Usually:

- unquoted variables
- unsafe filename iteration patterns

#### Should I learn systemd first or bash first?

In your track, sequence is right:

- first Bash safety baseline
- then systemd/journal helper scripts

---


### Pre-Commit Script Diagnostic Checklist

Before commit:

```bash
bash -n script.sh
shellcheck script.sh
```

Manual checks:

- correct `--help`/usage path
- invalid-arg behavior is clear
- paths with spaces tested
- dry-run path tested (if available)
- expected non-zero cases handled intentionally

---


### Deep Mini-Lab (45-60 minutes)

This lab combines lessons 5-7 into one practical flow.

#### Step 1. Prepare data

```bash
mkdir -p "/tmp/deep57/a b"
: > "/tmp/deep57/a b/one file.txt"
: > "/tmp/deep57/a b/two file.txt"
```

#### Step 2. Dry-run rename

```bash
./lessons/07-bash-scripting-automation/scripts/rename-ext.v2.sh -nv txt md "/tmp/deep57"
```

Verify old -> new mapping is correct.

#### Step 3. Real rename

```bash
./lessons/07-bash-scripting-automation/scripts/rename-ext.v2.sh -v txt md "/tmp/deep57"
```

#### Step 4. Backup with retention

```bash
./lessons/07-bash-scripting-automation/scripts/backup-dir.v2.sh "/tmp/deep57" --keep 2
./lessons/07-bash-scripting-automation/scripts/backup-dir.v2.sh "/tmp/deep57" --keep 2
ls -1t "$HOME"/backups/deep57_* | head -n 5
```

#### Step 5. Check backup logs

```bash
journalctl -t backup -n 20 --no-pager
```

#### Step 6. Unit triage

```bash
./lessons/07-bash-scripting-automation/scripts/devops-tail.v2.sh cron -s "1 hour ago" -n 100 || true
```

#### Step 7. APT simulation

```bash
sudo apt update
sudo apt-get -s upgrade | sed -n '1,40p'
```

#### Step 8. Cleanup

```bash
rm -rf /tmp/deep57
```
