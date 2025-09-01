# day7_en

# Bash Scripting

---

**Date:** **2025-08-27**

**Topic:** Bash scripting, templates, ShellCheck, backups, journal/systemd helpers

---

## Goals

- Write safe, readable Bash scripts using a common template.
- Practice file ops (bulk rename), archiving with rotation, and systemd/journal helpers.
- Adopt `shellcheck` as a pre-commit habit.

---

## Theory quick notes

- `set -Eeuo pipefail`: fail fast on unset vars/pipes; `trap` for diagnostics.
- Here-docs (`cat <<'SH' … SH`) for reproducible script blocks.
- `shellcheck your.sh` to catch common issues.
- Globs & parameter expansion: `${f%$ext}`, `${var:-default}`.
- Exit codes & `|| true` where you intentionally ignore failures.

---

## Step 1 — Warm-up

```bash
leprecha@Ubuntu-DevOps:~$ echo "$SHELL" && bash --version | head -1
/bin/bash
GNU bash, version 5.2.21(1)-release (x86_64-pc-linux-gnu)
leprecha@Ubuntu-DevOps:~$ mkdir -p tools labs/day7
```

- `echo "$SHELL"` → prints your default login shell (like `/bin/bash` or `/usr/bin/zsh`).
    
    Note: it shows the shell set in `/etc/passwd`, not necessarily the one you are currently running.
    
- `bash --version | head -1` → runs `bash` and shows its version, but only the first line.

---

## Step 2 — Safe template + ShellCheck

```bash
leprecha@Ubuntu-DevOps:~$ cat > tools/_template.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "ERR:$? at ${BASH_SOURCE[0]}:${LINENO}" >&2' ERR
usage(){ echo "Usage: $0 ..."; }
SH
```

`set -Eeuo pipefail`

Strict mode for safer, more predictable scripts:

- `-E` → makes the error trap (`trap ERR`) work inside functions and subshells.
- `-e` → exit immediately if any command fails (non-zero exit code).
- `-u` → error on undefined variables (catches typos early).
- `-o pipefail` → in a pipeline (`cmd1 | cmd2`), if *any* command fails, the whole pipeline fails (by default only the last command matters).

---

`IFS=$'\n\t'` — sets the **Internal Field Separator** (how Bash splits words).

By default it’s : *space, tab, efore commitnewline* → that breaks filenames with spaces.

Here we keep only newline and tab, so it’s safer for file handling.

---

`trap 'echo "ERR:$? at ${BASH_SOURCE[0]}:${LINENO}" >&2' ERR`

This sets a **trap** on the `ERR` signal.

- `ERR` is triggered when any command in the script fails (exit code ≠ 0).
- When that happens, the code inside `'...'` runs.

Breakdown:

- `"$?"` → the exit code of the last failed command.
- `${BASH_SOURCE[0]}` → the script’s filename (e.g., `myscript.sh`).
- `${LINENO}` → the line number where the error occurred.
- `>&2` → sends the message to **stderr**, so it doesn’t mix with normal output.

`usage(){ echo "Usage: $0 ..."; }` — This defines a `usage` function.

- The `{ ... }` is the function body.
- It prints a usage message: `Usage: scriptname ...`.
- `$0` → the script name as it was invoked.

**Install:**

```bash
leprecha@Ubuntu-DevOps:~$ sudo apt-get install -y shellcheck
```

---

## Practice

### 1) Bulk rename by extension (`tools/rename-ext.sh`)

- Args: `SRC_EXT DST_EXT DIR`. Loop files with `nullglob` and `mv` safely.
- Test: create `~/lab7` with a couple of `.txt`, convert to `.md`.

`rename-ext.sh`

```bash
leprecha@Ubuntu-DevOps:~$ cat > tools/rename-ext.sh << 'SH'
#!/usr/bin/env bash
set -Eeuo pipefail; IFS=$'\n\t'
usage(){ echo "Usage: $0 <src_ext> <dst_ext> <dir>"; }
[[ $# -eq 3 ]] || { usage; exit 1; }
src=".$1"; dst=".$2"; dir="$3"
[[ -d "$dir" ]] || { echo "No dir: $dir" >&2; exit 1; }
shopt -s nullglob
for f in "$dir"/*"$src"; do mv -- "$f" "${f%"$src"}$dst"; done
echo "Renamed in $dir: $src -> $dst"
SH
```

`usage(){ echo "Usage: $0 <src_ext> <dst_ext> <dir>"; }`— helper function showing usage.

---

`[[ $# -eq 3 ]] || {usage; exit 1; }` — Argument check.

- `$#` = number of arguments.
- If not equal to 3 → show usage and exit.

---

`src=".$1"; dst=".$2"; dir="$3"`  — assign arguments:

- `src` = old extension (e.g., `.txt`).
- `dst` = new extension (e.g., `.log`).
- `dir` = target directory.

---

 `[[ -d "$dir" ]] || { echo "No dir: $dir" >&2; exit 1 }` — verify directory exists. If not, print error to `stderr` and exit.

---

`shopt -s nullglob` — enable `nullglob` so that empty matches (like `*.txt` when none exist) expand to nothing, not the literal pattern.

---

`for f in "$dir"/*"$src"; do mv -- "$f" "${f%"$src"}$dst"; done`  — loop through matching files:

- `${f%$src}` = filename without extension.
- Append `$dst`.
- Rename with `mv`.

How to use:

```bash
leprecha@Ubuntu-DevOps:~$ chmod +x tools/rename-ext.sh
leprecha@Ubuntu-DevOps:~$ mkdir -p ~/lab7 && : > ~/lab7/a.txt && : > ~/lab7/b.txt
leprecha@Ubuntu-DevOps:~$ ./tools/rename-ext.sh txt md ~/lab7 && ls -1 ~/lab7 | head -5
Renamed in /home/leprecha/lab7: .txt -> .md
a.md
b.md
leprecha@Ubuntu-DevOps:~$ shellcheck tools/rename-ext.sh || true
```

---

`rename-ext.v2.sh (flags, spaces in paths)`

```bash
leprecha@Ubuntu-DevOps:~$ cat > tools/rename-ext.v2.sh << 'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
usage(){ echo "Usage: $0 [-n] [-v] <src_ext> <dst_ext> <dir>"; }
dry=0
verbose=0
while getopts ":nv" opt; do case "$opt" in n) dry=1;; v) verbose=1;; *) usage; exit 1;; esac; done
shift $((OPTIND-1))
[[ $# -eq 3 ]] || { usage; exit 1; }
src=".$1"
dst=".$2"
dir="$3"
[[ -d "$dir" ]] || { echo "No dir: $dir" >&2; exit 1; }
export src dst dry verbose
find "$dir" -type f -name "*$src" -print0 | while IFS= read -r -d '' f; do
new="${f%"$src"}$dst"
(( verbose )) && printf '%s -> %s\n' "$f" "$new"
(( dry )) || mv -- "$f" "$new"
done
SH
```

`dry=0; verbose=0` — Default flags:

- `dry=0` → not in dry-run mode.
- `verbose=0` → don’t print renames.

---

`while getopts ":nv" opt; do case "$opt" in n) dry=1;; v) verbose=1;; *) usage; exit 1;; esac; done` —  parse options with `getopts`, each found option goes into `opt`:

- `n` → enable dry-run.
- `v` → enable verbose.
- `*` — anything else → show usage + exit.

---

`shift $((OPTIND-1))` — drop parsed options from `$@`, leaving the 3 required args.

---

`export src dst dry verbose` — export variables so they’re visible inside the `while` loop.

---

`find "$dir" -type f -name "*$src" -print0 | while IFS= read -r -d '' f; do` —  use `find` to locate files:

- `type f` → files only.
- `name "*$src"` → names ending with the source extension (e.g., `*.txt`).
- `print0` → separate results with a **NUL** byte, not newline (safe for weird filenames).

`IFS= read -r -d '' f`:

- `IFS=` — don’t split on whitespace,
- `r` — don’t treat backslashes specially,
- `d ''` — read until NUL delimiter,
- `f` — variable holding each filename.

---

  `new="${f%"$src"}$dst"` —  **parameter expansion**: strip the shortest match of `$src` from the **end** of `$f`.

- `f=/path/file.txt`, `src=.txt` → `${f%"$src"}` = `/path/file`
- Append `$dst` → `/path/file.md`.

---

 `(( verbose )) && printf '%s -> %s\n' "$f" "$new"` — If `verbose=1`, print the rename action (`old → new`). 

- `printf '%s -> %s\n' "$f" "$new"` — safe, quoted, no surprises.

---

 `(( dry )) || mv -- "$f" "$new"` — If not in dry-run mode, actually move (rename) the file.

- if `dry=0`, do the move; if `dry=1`, skip it.

How to use:

```bash
leprecha@Ubuntu-DevOps:~$ chmod +x tools/rename-ext.v2.sh
leprecha@Ubuntu-DevOps:~$ mkdir -p ~/lab7/test
leprecha@Ubuntu-DevOps:~$ touch ~/lab7/test/file{1..3}.txt
leprecha@Ubuntu-DevOps:~$ ./tools/rename-ext.v2.sh -nv txt md ~/lab7/test
/home/leprecha/lab7/test/file3.txt -> /home/leprecha/lab7/test/file3.md
/home/leprecha/lab7/test/file2.txt -> /home/leprecha/lab7/test/file2.md
/home/leprecha/lab7/test/file1.txt -> /home/leprecha/lab7/test/file1.md
leprecha@Ubuntu-DevOps:~$ ./tools/rename-ext.v2.sh -v txt md ~/lab7/test
/home/leprecha/lab7/test/file3.txt -> /home/leprecha/lab7/test/file3.md
/home/leprecha/lab7/test/file2.txt -> /home/leprecha/lab7/test/file2.md
/home/leprecha/lab7/test/file1.txt -> /home/leprecha/lab7/test/file1.md
```

---

### 2) Dated backup with rotation (`tools/backup-dir.sh`)

- Args: `DIR [--keep N]`. Create `~/backups/NAME_YYYYmmdd_HHMM.tar.gz`; keep last N with `ls -1t … | tail -n +$((N+1)) | xargs -r rm -f`.

`backup-dir.sh`

```bash
leprecha@Ubuntu-DevOps:~$ cat > tools/backup-dir.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail; IFS=$'\n\t'
keep=5
[[ $# -ge 1 ]] || { echo "Usage: $0 <dir> [--keep N]"; exit 1; }
dir="$1"; shift || true
[[ "${1:-}" == "--keep" ]] && keep="${2:-5}"
[[ -d "$dir" ]] || { echo "No dir: $dir" >&2; exit 1; }
out=~/backups; mkdir -p "$out"
ts=$(date +%Y%m%d_%H%M); base=$(basename "$dir")
tarball="$out/${base}_${ts}.tar.gz"
tar -C "$(dirname "$dir")" -czf "$tarball" "$base"
ls -1t -- "$out"/"${base}"_* 2>/dev/null | tail -n +$((keep+1)) | tr '\n' '\0' | xargs -0 -r rm -f
echo "Created: $tarball (kept last $keep)"
SH
```

- `set -Eeuo pipefail; IFS=$'\n\t'` — strict Bash mode + safe splitting.

---

- `keep=5` — default retention count.

---

- `[[ $# -ge 1 ]] ...` — must provide at least one argument (directory).

---

- `dir="$1"; shift` — save dir argument, shift rest.

---

- `[[ "${1:-}" == "--keep" ]] && keep="${2:-5}"` — optional `-keep N`.

---

- `[[ -d "$dir" ]] ...` — check directory exists.

---

- `out=~/backups; mkdir -p "$out"` — ensure backups folder exists.

---

- `ts=$(date +%Y%m%d_%H%M)` — timestamp.

---

- `base=$(basename "$dir")` — just the last part of path.
    
    ---
    
- `tarball="$out/${base}_${ts}.tar.gz"` — final archive name.

---

- `tar -C "$(dirname "$dir")" -czf "$tarball" "$base"` — compress without absolute paths.

---

- `ls -1t -- "$out"/"${base}"_* 2>/dev/null | tail -n +$((keep+1)) | tr '\n' '\0' | xargs -0 -r rm -f` — keep newest N, remove the rest.

---

- `echo "Created: $tarball (kept last $keep)"` — success message.

How to use:

```bash
leprecha@Ubuntu-DevOps:~$ chmod +x tools/backup-dir.sh
leprecha@Ubuntu-DevOps:~$ ./tools/backup-dir.sh ~/lab7 --keep 3 && ls -l ~/backups | head
Created: /home/leprecha/backups/lab7_20250827_1359.tar.gz (kept last 3)
total 4
-rw-r--r-- 1 leprecha sysadmin 161 Aug 27 13:59 lab7_20250827_1359.tar.gz
leprecha@Ubuntu-DevOps:~$ shellcheck tools/backup-dir.sh || true

In tools/backup-dir.sh line 12:
ls -1t -- "$out"/"${base}"_* 2>/dev/null | tail -n +$((keep+1)) | tr '\n' '\0' | xargs -0 -r rm -f
^-- SC2012 (info): Use find instead of ls to better handle non-alphanumeric filenames.

For more information:
  https://www.shellcheck.net/wiki/SC2012 -- Use find instead of ls to better ...
  
# Script works fine, just ShellCheck warning for now.
```

---

`backup-dir.v2.sh (flock, exclude, logger)`

```bash
leprecha@Ubuntu-DevOps:~$ cat > tools/backup-dir.v2.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail; IFS=$'\n\t'
keep=5; exclude=''; dir=''
while [[ $# -gt 0 ]]; do
case "$1" in
--keep) keep="${2:-5}"; shift 2;;
--exclude) exclude="${2:-}"; shift 2;;
*) dir="${1}"; shift;; esac done
[[ -n "$dir" && -d "$dir" ]] || { echo "Usage: $0 <dir> [--keep N] [--exclude PATTERN]"; exit 1; }
out="$HOME/backups"; mkdir -p -- "$out"
ts=$(date +%Y%m%d_%H%M%S); base=$(basename -- "$dir")
tarball="$out/${base}_${ts}.tar.gz"
lock="/tmp/backup-$base.lock"
cmd=(tar -C "$(dirname -- "$dir")" -czf "$tarball")
[[ -n "$exclude" ]] && cmd+=("--exclude=$exclude")
cmd+=("$base")
{ flock -n 9 || { echo "Another backup is in progress for $base" >&2; exit 1; }
"${cmd[@]}"
tar -tzf "$tarball" >/dev/null
} 9> "$lock"
logger -t backup "Created $tarball"
find "$out" -maxdepth 1 -type f -name "${base}_*.tar.gz" -printf "%T@ %p\n" | sort -rn | tail -n +$((keep+1)) | cut -d' ' -f2- | xargs -r rm -f
echo "OK: $tarball (keep last $keep)"
SH
```

`while [[ $# -gt 0 ]]; do` — loop while there are CLI args — parse them.

---

`case` on the first argument (`$1`).

---

 `--keep) keep="${2:-5}"; shift 2;;` — If `--keep`, read next value (fallback `5`), shift by 2.

---

`--exclude) exclude="${2:-}"; shift 2;;` — If `--exclude`, read pattern (or empty), shift by 2.

---

`[[ -n "$dir" && -d "$dir" ]]` — `dir` must be set and a directory; else print Usage and exit 1.

---

`out="$HOME/backups"; mkdir -p -- "$out"` — backup dir is `~/backups`; create it idempotently. `--` guards against dash-prefixed names.

---

`tarball="$out/${base}_${ts}.tar.gz"` — full path of the archive: `~/backups/<base>_<ts>.tar.gz`.

---

`lock="/tmp/backup-$base.lock"` — lock file for mutual exclusion: `/tmp/backup-<base>.lock`.

---

`cmd=(tar -C "$(dirname -- "$dir")" -czf "$tarball")` — build `tar` command array: change to target’s parent (`-C dirname(dir)`), create gzip archive `-czf` at `tarball`.

---

`[[ -n "$exclude" ]] && cmd+=("--exclude=$exclude")` — If `--exclude` provided, append `--exclude=<pattern>`.

---

`cmd+=("$base")` — add the `base` directory (relative to `-C`) to the archive.

---

`{ flock -n 9 || { echo "Another backup is in progress for $base" >&2; exit 1; } 9> "$lock" }` — non-blocking `flock` on FD 9 then FD 9 is redirected to the `lockfile`.

---

`"${cmd[@]}"` — run the composed `tar` command. Array `cmd` preserves quoting/whitespace safely.

---

`tar -tzf "$tarball" >/dev/null` — verify archive integrity via `tar -tzf`.

---

`logger -t backup "Created $tarball"` — log to syslog with tag `backup`: “Created <tarball>”.

---

`find "$out" -maxdepth 1 -type f -name "${base}_*.tar.gz" -printf "%T@ %p\n" | sort -rn | tail -n +$((keep+1)) | cut -d' ' -f2- | xargs -r rm -f`

Archive rotation:

`find … -printf "%T@ %p\n”` — mtime + path;

`sort -rn` — newest first;

`tail -n +$((keep+1))` — items after the first keep;

`cut -d' ' -f2-` — drop time, keep path;

`xargs -r rm -f` — delete extras.

How to use:

```bash
leprecha@Ubuntu-DevOps:~$ mkdir -p /tmp/demo/a/{b,c}; echo hi >/tmp/demo/a/b/hi.txt
leprecha@Ubuntu-DevOps:~$ ./tools/backup-dir.v2.sh /tmp/demo
OK: /home/leprecha/backups/demo_20250828_210442.tar.gz (keep last 5)
#The script creates a compressed archive (tar.gz) of /tmp/demo and stores it in ~/backups.
leprecha@Ubuntu-DevOps:~$ ./tools/backup-dir.v2.sh /tmp/demo --keep 2
OK: /home/leprecha/backups/demo_20250828_210447.tar.gz (keep last 2)
#Another archive is made, but now the script is told to keep only the last 2 backups. Older ones beyond the limit get deleted.
leprecha@Ubuntu-DevOps:~$ ./tools/backup-dir.v2.sh /tmp/demo --exclude 'demo/a/b/*' --keep 3
OK: /home/leprecha/backups/demo_20250828_210544.tar.gz (keep last 3)
#Creates another archive, excluding everything under demo/a/b/* (hi.txt won’t be in the backup).It also keeps only the last 3 backups.
leprecha@Ubuntu-DevOps:~$ ls -lt ~/backups | head
total 12
-rw-r--r-- 1 leprecha sysadmin 160 Aug 28 21:05 demo_20250828_210544.tar.gz
-rw-r--r-- 1 leprecha sysadmin 197 Aug 28 21:04 demo_20250828_210447.tar.gz
-rw-r--r-- 1 leprecha sysadmin 197 Aug 28 21:04 demo_20250828_210442.tar.gz
leprecha@Ubuntu-DevOps:~$ tar -tzf "$(ls -1t ~/backups/demo_* | head -1)" | head
demo/
demo/a/
demo/a/c/
demo/a/b/

#This finds the latest backup file, lists its contents, and shows the first 10 lines.You see demo/, demo/a/, demo/a/c/, and demo/a/b/, but no hi.txt inside b/.
```

---

### 3) Journal/systemd helper (`tools/devops-tail.sh`)

- Args: `unit [--since "..."]`. Show `systemctl status` header and last 50 log lines.

`devops-tail.sh`

```bash
cat > tools/devops-tail.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail; IFS=$'\n\t'
[[ $# -ge 1 ]] || { echo "Usage: $0 <unit> [--since '1 hour ago']"; exit 1; }
unit="$1"; shift || true
since="10 min ago"
[[ "${1:-}" == "--since" ]] && since="${2:-$since}"
echo "== systemctl status $unit =="; systemctl status "$unit" --no-pager | sed -n '1,12p'
echo "== journalctl -u $unit --since '$since' =="; journalctl -u "$unit" --since "$since" -n 50 --no-pager
SH
```

`[[ $# -ge 1 ]] || { echo "Usage: $0 <unit> [--since '1 hour ago']"; exit 1; }` — need at least one argument. Otherwise print usage and exit.

---

`unit="$1"; shift || true` — save first argument (unit name, e.g. `cron`), then remove it from argument list.

---

`since="10 min ago"` — Default lookback = “10 min ago”.
`[[ "${1:-}" == "--since" ]] && since="${2:-$since}"` — If user wrote `--since X`, replace with provided value (`$2`).

---

`echo "== systemctl status $unit =="; systemctl status "$unit" --no-pager | sed -n '1,12p'` — print header, then show first 12 lines of `systemctl status` (overview only, no pager).

---

`echo "== journalctl -u $unit --since '$since' =="; journalctl -u "$unit" --since "$since" -n 50 --no-pager` — print header, then show last 50 log lines from journalctl since given time.

How to use:

```bash
leprecha@Ubuntu-DevOps:~$ chmod +x tools/devops-tail.sh
leprecha@Ubuntu-DevOps:~$ ./tools/devops-tail.sh cron --since "15 min ago" || true
== systemctl status cron ==
● cron.service - Regular background program processing daemon
     Loaded: loaded (/usr/lib/systemd/system/cron.service; enabled; preset: enabled)
    Drop-In: /etc/systemd/system/cron.service.d
             └─override.conf
     Active: active (running) since Wed 2025-08-27 10:10:26 IST; 4h 26min ago
       Docs: man:cron(8)
   Main PID: 1112 (cron)
      Tasks: 1 (limit: 18465)
     Memory: 3.6M (peak: 11.2M)
        CPU: 932ms
     CGroup: /system.slice/cron.service
             └─1112 /usr/sbin/cron -f -P
== journalctl -u cron --since '15 min ago' ==
Aug 27 14:25:01 Ubuntu-DevOps CRON[8955]: pam_unix(cron:session): session opened for user root(uid=0) by root(uid=0)
Aug 27 14:25:01 Ubuntu-DevOps CRON[8955]: pam_unix(cron:session): session closed for user root
Aug 27 14:30:01 Ubuntu-DevOps CRON[9007]: pam_unix(cron:session): session opened for user root(uid=0) by root(uid=0)
Aug 27 14:30:01 Ubuntu-DevOps CRON[9010]: (root) CMD ([ -x /etc/init.d/anacron ] && if [ ! -d /run/systemd/system ]; then /usr/sbin/invoke-rc.d anacron start >/dev/null; fi)
Aug 27 14:30:01 Ubuntu-DevOps CRON[9007]: pam_unix(cron:session): session closed for user root
Aug 27 14:35:01 Ubuntu-DevOps CRON[9038]: pam_unix(cron:session): session opened for user root(uid=0) by root(uid=0)
Aug 27 14:35:01 Ubuntu-DevOps CRON[9038]: pam_unix(cron:session): session closed for user root
leprecha@Ubuntu-DevOps:~$ shellcheck tools/devops-tail.sh || true
```

---

`devops-tail.v2.sh (getopts: -s/-n/-f/-p)`

```bash
leprecha@Ubuntu-DevOps:~$ cat > tools/devops-tail.v2.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
usage(){ echo "Usage: $0 <unit> [-s 'since'] [-n lines] [-f] [-p PRIORITY]"; }
since="10 min ago"; lines=50; follow=0; prio=""; unit=""
OPTIND=1
while getopts ":s:n:fp:h" opt; do
case "$opt" in
s) since="$OPTARG" ;;
n) lines="$OPTARG" ;;
f) follow=1 ;;
p) prio="$OPTARG" ;;
h) usage; exit 0 ;;
\?) usage; exit 1 ;;
esac
done
shift $((OPTIND-1))
if [[ $# -gt 0 && "${1:-}" != -* ]]; then
unit="$1"
shift
fi
if [[ $# -gt 0 ]]; then
OPTIND=1
while getopts ":s:n:fp:h" opt; do
case "$opt" in
s) since="$OPTARG" ;;
n) lines="$OPTARG" ;;
f) follow=1 ;;
p) prio="$OPTARG" ;;
h) usage; exit 0 ;;
\?) usage; exit 1 ;;
esac
done
shift $((OPTIND-1)) || true
fi
[[ -n "$unit" ]] || { usage; exit 1; }
[[ "$lines" =~ ^[0-9]+$ ]] && (( lines>=1 )) || { echo "Invalid -n LINES: $lines" >&2; exit 1; }
echo "== systemctl status $unit =="
systemctl status "$unit" --no-pager | sed -n '1,12p' || true
args=(-u "$unit" --since "$since" -n "$lines" --no-pager)
[[ -n "$prio" ]] && args+=(-p "$prio")
(( follow )) && args+=(-f)
printf '== journalctl %s ==\n' "$(printf '%s ' "${args[@]}")"
journalctl "${args[@]}"
SH
```

`since="10 min ago"; lines=50; follow=0; prio=""` — default values: show logs since 10 minutes ago, 50 lines, don’t follow, no priority filter.

---

Parse command-line options:

- `s` takes an argument → set `since`.
- `n` takes an argument → number of lines.
- `f` (no arg) → follow mode (like `tail -f`).
- `p` takes argument → priority filter (`warning`, `info`, `3`, etc).
- `h` and `\?`→ unknown option → shows help; unknown options cause usage+exit.

---

`OPTIND=1` — reset `getopts` index (defensive).

---

`while getopts ":s:n:fp:h" opt; do` — first `getopts` pass: parse options **before** positional args.

---

`shift $((OPTIND-1))` — discard parsed options from `$@`.

---

`[[ -n "$unit" ]] || { usage; exit 1; }` — If the next arg is **not** an option, treat it as the unit name (e.g., `cron`) and shift it off.

---

`if [[ $# -gt 0 ]]; then` … `shift $((OPTIND-1)) || true fi` — second `getopts` pass: parse options **after** the unit. This enables both orders: `cron -s "1 hour ago"` **and** `-s "1 hour ago" cron`.

---

`[[ -n "$unit" ]] || { usage; exit 1; }` — unit is required.

---

`[[ "$lines" =~ ^[0-9]+$ ]] && (( lines>=1 )) || { echo "Invalid -n LINES: $lines" >&2; exit 1; }` — validate that `-n` is an integer ≥ 1.

---

`args=(-u "$unit" --since "$since" -n "$lines" --no-pager)` — build base `journalctl` arguments into an array.

---

`[[ -n "$prio" ]] && args+=(-p "$prio")` — add `-p` if a priority is specified.

---

`(( follow )) && args+=(-f)` — add `-f` if follow mode is requested.

---

`printf '== journalctl %s ==\n' "$(printf '%s ' "${args[@]}")”` — one-line header.

---

`journalctl "${args[@]}"` — run `journalctl` with the assembled arguments. With `-f`, it will keep streaming until you `Ctrl+C`.

How to use:

```bash
./tools/devops-tail.v2.sh cron -s "1 hour ago"
#Shows cron service status (first 12 lines of systemctl status).
#Then prints logs from cron unit for the last 1 hour (default 50 lines).
./tools/devops-tail.v2.sh cron -n 200
#Shows cron service status.
#Logs for the last 10 minutes (default --since), up to 200 lines.
./tools/devops-tail.v2.sh cron -f
#Shows cron status.
#Logs for the last 10 minutes (default), 50 lines.
#Then stays open in follow mode, streaming new log entries.
#Stop with Ctrl+C.
./tools/devops-tail.v2.sh cron -p warning -s "1 hour ago" -n 200
#Shows cron status.
#Logs from the last 1 hour, up to 200 lines, but only with priority warning or higher.
#Since cron usually logs at info, you’ll often get no entries.
```

All flags work, headers are displayed in a single line.

---

## Optional hard ideas

- Add `getopts` to `devops-tail.sh` (`-s`, `-n`, `-f`), and to `backup-dir.sh` (keep).
- Use `flock` to serialize backups; add `logger -t backup "Created: $tarball"`.
- Create a temporary workspace with `mktemp -d` and clean up in `trap`.

---

## Summary

- Built a **safe Bash template** (`set -Eeuo pipefail`, strict `IFS`, `trap` with line/exit code) and adopted **ShellCheck** before commit.
- Implemented **bulk rename**:
    - v1: simple loop with `nullglob`, safe `mv`.
    - v2: robust version with `getopts` ( `-n` dry-run, `-v` verbose), `find -print0 … read -r -d ''` for spaces in paths.
- Implemented **dated backups with rotation**:
    - v1: `tar` into `~/backups/NAME_YYYYmmdd_HHMM.tar.gz`, keep N latest.
    - v2: added `flock` (no parallel runs), `--exclude`, and `logger` integration.
- Implemented **systemd/journal helper**:
    - v1: show `systemctl status` header + last 50 log lines.
    - v2: `getopts` flags: `s/--since`, `n/--lines`, `f/--follow`, `p PRIORITY`.
- Verified with tests: files **with spaces**, dry-run behavior, parallel backup lock, `journalctl` filters. All scripts pass **ShellCheck** (or have documented ignores).

---

## **Key takeaways:**

Adopted a safe Bash template, disciplined quoting and `[[ ]]`, and a ShellCheck-before-commit routine. Built practical tooling for file ops, backups with rotation/locking, and fast journal/systemd introspection.

---

## **Next steps (Day 8 preview):**

grep/sed/awk pipelines for log parsing, `find -print0 | xargs -0` patterns, and small data-munging one-liners that feed into your `devops-tail` outputs.

---

---

### Tests

- Rename: created `~/lab7/{a b}.txt`, ran `-n` and real run; paths with spaces OK.
- Backup: two concurrent runs → second blocked by `flock`; `-exclude node_modules` worked; rotation kept last N.
- Logs: `./tools/devops-tail.v2.sh cron -s "1 hour ago" -n 200 -p warning` produced expected output.

---

## Artifacts

- `tools/_template.sh`
- `tools/rename-ext.sh`
- `tools/rename-ext.v2.sh`
- `tools/backup-dir.sh`
- `tools/backup-dir.v2.sh`
- `tools/devops-tail.sh`
- `tools/devops-tail.v2.sh`

**Tooling dependency** — `shellcheck` 

---

## To repeat

- Template (`set -Eeuo pipefail`, `IFS`, `trap`)
- Quoting & `[[ ]]`, forwarding `"$@"`
- `shopt -s nullglob`, parameter expansion
- `shellcheck` before commit