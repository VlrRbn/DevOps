# lesson_08

# Text Processing for Ops (grep/sed/awk)

---

**Date: 2025-08-30**

**Topic: grep/sed/awk, journalctl pipelines, mini-tools**

---

## Goals

- Search and filter logs efficiently with **grep** (regex, case-insensitive, invert, recursive).
- Edit configs safely with **sed** on **copies** (in-place with backup).
- Summarize logs with **awk** (columns, counters, small reports).
- Package repeatable pipelines as small scripts under `tools/`.

---

## Environment prep

```bash
leprecha@Ubuntu-DevOps:~$ mkdir -p labs/lesson_08/mock labs/lesson_08/logs/sample tools
leprecha@Ubuntu-DevOps:~$ ls -l /var/log/auth.log* 2>/dev/null || true
leprecha@Ubuntu-DevOps:~$ journalctl -t ssh --since "today" -n 5 --no-pager || true
-rw-r----- 1 syslog adm  21000 Aug 30 12:25 /var/log/auth.log
-rw-r----- 1 syslog adm 449783 Aug 29 18:00 /var/log/auth.log.1
-- No entries --
```

---

## Cheat sheet

- grep: `grep -nE "something" file`, `grep -rE "something" dir`, invert `-v`, ignore case `-i`

`grep` — used to search for lines that match a pattern (regular expression).

Search in `file` for lines containing `"something"`.

- `-n` shows line numbers
- `-E` enables extended regex

---

- sed: `sed -n '1,80p' file`, in-place+backup: `sed -ri.bak 's/old/new/' file`

`sed` — Stream editor - edits text on the fly.

Replace `old` with `new` directly in the file.

- `-r`→ use extended regex
- `-i.bak` → edit in place, but save a backup with `.bak` extension

---

- awk: fields `$1..$NF`, record `NR`, field count `NF`, e.g. `awk '{print NR,$1,$NF}' file`

`awk` — a text-processing language, great for structured/tabular data.

Fields (`$1`, `$2`, …, `$NF`) are words in a line (split by spaces).

- `NR` → current line number
- `NF` → number of fields (words) in the line

---

- journal → grep → awk: `journalctl -u <unit> -o cat | grep -E "pat" | awk '…'`
- `-o cat` → print only the log message (no extra metadata)
- `grep -E "pat"` → filter logs by a pattern
- `awk '…'` → parse further (extract fields, count, reformat, etc.)

---

`-u ssh` filters by systemd unit, `-t sshd` filters by log tag; use whichever gives the desired log coverage.

---

## Practice

Install the SSH server:

```bash
leprecha@Ubuntu-DevOps:~$ sudo apt update
leprecha@Ubuntu-DevOps:~$ sudo apt install -y openssh-server
```

Start it and enable autostart:

```bash
leprecha@Ubuntu-DevOps:~$ sudo systemctl enable --now ssh
Synchronizing state of ssh.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
Executing: /usr/lib/systemd/systemd-sysv-install enable ssh
Created symlink /etc/systemd/system/sshd.service → /usr/lib/systemd/system/ssh.service.
Created symlink /etc/systemd/system/multi-user.target.wants/ssh.service → /usr/lib/systemd/system/ssh.service.
leprecha@Ubuntu-DevOps:~$ systemctl status ssh --no-pager
● ssh.service - OpenBSD Secure Shell server
     Loaded: loaded (/usr/lib/systemd/system/ssh.service; enabled; preset: enabled)
     Active: active (running) since Sat 2025-08-30 12:58:49 IST; 6s ago
TriggeredBy: ● ssh.socket
       Docs: man:sshd(8)
             man:sshd_config(5)
    Process: 6601 ExecStartPre=/usr/sbin/sshd -t (code=exited, status=0/SUCCESS)
   Main PID: 6602 (sshd)
      Tasks: 1 (limit: 18465)
     Memory: 1.2M (peak: 2.0M)
        CPU: 18ms
     CGroup: /system.slice/ssh.service
             └─6602 "sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups"

Aug 30 12:58:49 Ubuntu-DevOps systemd[1]: Starting ssh.service - OpenBSD Secure Shell server...
Aug 30 12:58:49 Ubuntu-DevOps sshd[6602]: Server listening on 0.0.0.0 port 22.
Aug 30 12:58:49 Ubuntu-DevOps sshd[6602]: Server listening on :: port 22.
Aug 30 12:58:49 Ubuntu-DevOps systemd[1]: Started ssh.service - OpenBSD Secure Shell server.

```

Check that port 22 is listening:

```bash
leprecha@Ubuntu-DevOps:~$ sudo ss -tnlp | grep ssh
#ss — modern utility to inspect sockets (replacement for netstat)
#-t → show TCP sockets only.
#-n → don’t resolve names (show raw IP/port numbers).
#-l → show listening sockets (not all connections).
#-p → show process info (PID/program using the socket)
LISTEN 0      4096         0.0.0.0:22        0.0.0.0:*    users:(("sshd",pid=6602,fd=3),("systemd",pid=1,fd=383))                                                                                                                                 
LISTEN 0      4096            [::]:22           [::]:*    users:(("sshd",pid=6602,fd=4),("systemd",pid=1,fd=387))        
```

Test connecting to yourself:

```bash
leprecha@Ubuntu-DevOps:~$ ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no $USER@localhost
The authenticity of host 'localhost (127.0.0.1)' can't be established.
ED25519 key fingerprint is SHA256:CjQ/nzJKCRIHHV4ERNMVI3Paji/IFJXLBb5r8pe1YQk.
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added 'localhost' (ED25519) to the list of known hosts.
leprecha@localhost's password: 
Permission denied, please try again.
leprecha@localhost's password: 
Welcome to Ubuntu 24.04.3 LTS (GNU/Linux 6.14.0-28-generic x86_64)
```

— Enter a wrong password → you’ll see `Failed password` in `auth.log` / `journalctl`.

— Enter the correct one → you’ll see `Accepted password`.

---

### 1) grep triage (auth/syslog/journal)

Pick what exists on your box.

```bash
# SSH attempts in auth.log (if present)
leprecha@Ubuntu-DevOps:~$ sudo grep -nE "Failed password|Accepted password" /var/log/auth.log | head -20
223:2025-08-30T12:59:52.346509+01:00 Ubuntu-DevOps sshd[6620]: Failed password for leprecha from 127.0.0.1 port 44752 ssh2
224:2025-08-30T12:59:56.988653+01:00 Ubuntu-DevOps sshd[6620]: Accepted password for leprecha from 127.0.0.1 port 44752 ssh2
239:2025-08-30T13:06:22.872367+01:00 Ubuntu-DevOps sudo: leprecha : TTY=pts/1 ; PWD=/home/leprecha ; USER=root ; COMMAND=/usr/bin/grep -nE 'Failed password|Accepted password' /var/log/auth.log

# Same, from systemd journal
leprecha@Ubuntu-DevOps:~$ journalctl -u ssh --since "today" -o cat | grep -nE "Failed password|Accepted" | head -20
6:Failed password for leprecha from 127.0.0.1 port 44752 ssh2
7:Accepted password for leprecha from 127.0.0.1 port 44752 ssh2

# Quick scan for error-ish lines across logs
leprecha@Ubuntu-DevOps:~$ sudo grep -nEi "error|fail|critical" /var/log/* 2>/dev/null | head -5
/var/log/apport.log.1:1:ERROR: apport (pid 15583) 2025-08-22 12:02:21,178: host pid 15551 crashed in a container without apport support
/var/log/apport.log.1:2:ERROR: apport (pid 15630) 2025-08-22 12:02:33,096: host pid 15606 crashed in a container without apport support
/var/log/apport.log.1:3:ERROR: apport (pid 15670) 2025-08-22 12:02:42,537: host pid 15648 crashed in a container without apport support
/var/log/apport.log.1:4:ERROR: apport (pid 16121) 2025-08-22 12:04:46,933: host pid 16097 crashed in a container without apport support
/var/log/auth.log:101:2025-08-29T21:13:37.855913+01:00 Ubuntu-DevOps dbus-daemon[1162]: [system] Rejected send message, 0 matched rules; type="method_return", sender=":1.78" (uid=1000 pid=2424 comm="/usr/bin/wireplumber" label="unconfined") interface="(unset)" member="(unset)" error name="(unset)" requested_reply="0" destination=":1.5" (uid=0 pid=1160 comm="/usr/libexec/bluetooth/bluetoothd" label="unconfined")
```

---

### 2) sed mock edit (safe in-place on a copy)

Never edit /etc directly in practice — copy first.

```bash
leprecha@Ubuntu-DevOps:~$ sudo cp /etc/ssh/sshd_config labs/lesson_08/mock/sshd_config || true
leprecha@Ubuntu-DevOps:~$ sudo chown "$(id -un)":"$(id -gn)" labs/lesson_08/mock/sshd_config 2>/dev/null || true

leprecha@Ubuntu-DevOps:~$ sed -n '1,80p' labs/lesson_08/mock/sshd_config | nl | sed -n '1,7p'
     1	# This is the sshd server system-wide configuration file.  See
     2	# sshd_config(5) for more information.
     3	# This sshd was compiled with PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games
     4	# The strategy used for options in the default sshd_config shipped with
     5	# OpenSSH is to specify options with their default value where
     6	# possible, but leave them commented.  Uncommented options override the
     7	# default value.

# toggle PasswordAuthentication to no (with backup)
leprecha@Ubuntu-DevOps:~$ sed -ri.bak 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication no/' labs/lesson_08/mock/sshd_config

# verify & diff grep
leprecha@Ubuntu-DevOps:~$ grep -nE '^#?PasswordAuthentication' labs/lesson_08/mock/sshd_config
66:PasswordAuthentication no
leprecha@Ubuntu-DevOps:~$ diff -u labs/lesson_08/mock/sshd_config{.bak,} | sed -n '1,10p'
--- labs/lesson_08/mock/sshd_config.bak	2025-08-30 13:19:38.109775388 +0100
+++ labs/lesson_08/mock/sshd_config	2025-08-30 13:24:44.456610728 +0100
@@ -63,7 +63,7 @@
 # IgnoreRhosts yes
 # To disable tunneled clear text passwords, change to no here!
-#PasswordAuthentication yes
+PasswordAuthentication no
 #PermitEmptyPasswords no
 # Change to yes to enable challenge-response passwords (beware issues with

# restore # mv labs/lesson_08/mock/sshd_config{.bak,}
```

`sed -ri.bak 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication no/'`

- `-r` — use extended regular expressions.
- `-i.bak` — edit the file **in place**, saving a backup with the `.bak` extension.
- Regex replaces any `PasswordAuthentication ...` line (commented or not) with: `PasswordAuthentication no`

---

`diff -u labs/lesson_08/mock/sshd_config{.bak,}`

- `{.bak,}` → Bash brace expansion: expands into `labs/lesson_08/mock/sshd_config.bak` and `labs/lesson_08/mock/sshd_config`.
- `diff -u` — compares files in “unified” format.

---

### 3) awk report (nginx-style access log)

If you don’t have real logs, create a sample.

```bash
cat > labs/lesson_08/logs/sample/nginx_access.log <<'LOG'
127.0.0.1 - - [10/Jul/2025:13:55:36 +0000] "GET /index.html HTTP/1.1" 200 1024 "-" "curl/8.0"
10.0.0.5  - - [10/Jul/2025:13:55:37 +0000] "GET /api/v1/users HTTP/1.1" 200 512 "-" "Mozilla"
10.0.0.5  - - [10/Jul/2025:13:55:38 +0000] "POST /api/v1/login HTTP/1.1" 401 0 "-" "Mozilla"
192.168.0.2 - - [10/Jul/2025:13:55:39 +0000] "GET /api/v1/users HTTP/1.1" 500 0 "-" "curl/8.0"
LOG
leprecha@Ubuntu-DevOps:~$ awk '{status=$9; path=$7; ip=$1; total++; codes[status]++; hits[path]++; ips[ip]++} END {
     printf "Total: %d\n", total;
     printf "Status codes:\n"; for (c in codes) printf "  %s: %d\n", c, codes[c];
     printf "Top paths:\n"; for (p in hits) printf "  %s: %d\n", p, hits[p];
     printf "Unique IPs: %d\n", length(ips);
}' labs/lesson_08/logs/sample/nginx_access.log
Total: 4
Status codes:
  401: 1
  200: 2
  500: 1
Top paths:
  /api/v1/login: 1
  /index.html: 1
  /api/v1/users: 2
Unique IPs: 3
```

### Writing the sample nginx log

- Lines follow nginx **combined** format: `IP user ident [time] "METHOD PATH HTTP/…" status bytes "referer" "user-agent"`.

---

### AWK aggregation

- Default field separator is whitespace; for combined logs that makes:
    - `ip=$1`, `path=$7` (second token inside`"$6 $7 $8"`), `status=$9`, `bytes=$10`.
- Arrays:
    - `codes[status]++`, `hits[path]++`, `ips[ip]++`.
    - `total++` counts rows.
- `END` prints totals, per-status counts, per-path counts, and `length(ips)` as unique IPs.

---

### 4) Tooling up (package useful pipelines)

**A) SSH failures report (journal or auth.log)**

```bash
cat > tools/log-ssh-fail-report.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
src="${1:-journal}"
if [[ "$src" == "auth" && -f /var/log/auth.log ]]; then
sudo zgrep -hE "Failed password" /var/log/auth.log* || true
else
sudo journalctl -t sshd --since "today" -o cat 2>/dev/null | grep -E "Failed password|Invalid user|Disconnected from invalid user" || true
fi | awk '{for(i=1;i<=NF;i++) if ($i=="from") {ip=$(i+1); gsub(/^[\[\(]+|[\]\),;]+$/,"",ip); print ip; break}}' | sort | uniq -c | sort -nr | head -10
SH
leprecha@Ubuntu-DevOps:~$ chmod +x tools/log-ssh-fail-report.sh
leprecha@Ubuntu-DevOps:~$ tools/log-ssh-fail-report.sh
      2 127.0.0.1
```

`src="${1:-journal}"` — variable is set from the first script argument (`$1`). Defaults to `"journal"` if not provided.

---

`if [[ "$src" == "auth" && -f /var/log/auth.log ]]; then` — If `src` equals `"auth"` **and** `/var/log/auth.log` exists → use auth.log files.

---

`sudo zgrep -hE "Failed password" /var/log/auth.log* || true` — search for `"Failed password"` in all `auth.log` files.

- `zgrep` handles gzip.
- `-h` suppresses filenames.
- `-E` enables extended regex.
- `|| true` avoids error exit if nothing is found.

---

`else sudo journalctl -t sshd --since "today" -o cat 2>/dev/null  | grep -E` — otherwise, read systemd journal:

- `-t sshd` → only sshd messages.
- `-since "today"` → only today’s logs.
- `-o cat` → raw message text.

---

`fi | awk '{for(i=1;i<=NF;i++) if ($i=="from") {ip=$(i+1); gsub(/^[\[\(]+|[\]\),;]+$/,"",ip); print ip; break}}’` — pipe all that into `awk`:

- Loops over fields in each line.
- If the word `"from"` is found, takes the next field (IP).
- `gsub(...)` cleans brackets, commas, etc.

---

`| sort | uniq -c | sort -nr` — `sort` the IPs, `uniq -c` count duplicates, `sort -nr` sort numerically in reverse (highest first).

---

**B) Grep helper (file or dir)**

```bash
cat > tools/log-grep.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -ge 2 ]] || { echo "Usage: $0 <pattern> <file_or_dir> [grep-opts...]"; exit 1; }
pattern="$1"; target="$2"; shift 2
if [[ -d "$target" ]]; then
grep -rEn --color=always "$@" -e "$pattern" -- "$target"
else
grep -nE --color=always "$@" -e "$pattern" -- "$target"
fi
SH

leprecha@Ubuntu-DevOps:~$ chmod +x tools/log-grep.sh
leprecha@Ubuntu-DevOps:~$ ./tools/log-grep.sh "Failed password|Accepted password" /var/log/auth.log | head -10 || true
2025-08-30T12:48:44.964540+01:00 Ubuntu-DevOps sudo: leprecha : TTY=pts/0 ; PWD=/home/leprecha ; USER=root ; COMMAND=/usr/bin/grep -nE 'Failed password|Accepted password' /var/log/auth.log
2025-08-30T12:53:06.347445+01:00 Ubuntu-DevOps sudo: leprecha : TTY=pts/0 ; PWD=/home/leprecha ; USER=root ; COMMAND=/usr/bin/grep -nE 'Failed password|Accepted password' /var/log/auth.log
2025-08-30T12:59:52.346509+01:00 Ubuntu-DevOps sshd[6620]: Failed password for leprecha from 127.0.0.1 port 44752 ssh2
2025-08-30T12:59:56.988653+01:00 Ubuntu-DevOps sshd[6620]: Accepted password for leprecha from 127.0.0.1 port 44752 ssh2
2025-08-30T13:06:22.872367+01:00 Ubuntu-DevOps sudo: leprecha : TTY=pts/1 ; PWD=/home/leprecha ; USER=root ; COMMAND=/usr/bin/grep -nE 'Failed password|Accepted password' /var/log/auth.log
2025-08-30T13:07:29.370213+01:00 Ubuntu-DevOps sudo: leprecha : TTY=pts/1 ; PWD=/home/leprecha ; USER=root ; COMMAND=/usr/bin/grep -nE 'Failed password|Accepted password' /var/log/auth.log

#If we want to separate sudo logs from sshd logs, we can add a filter in grep:
leprecha@Ubuntu-DevOps:~$ ./tools/log-grep.sh "sshd.*(Failed password|Accepted password)" /var/log/auth.log
2025-08-30T12:59:52.346509+01:00 Ubuntu-DevOps sshd[6620]: Failed password for leprecha from 127.0.0.1 port 44752 ssh2
2025-08-30T12:59:56.988653+01:00 Ubuntu-DevOps sshd[6620]: Accepted password for leprecha from 127.0.0.1 port 44752 ssh2
2025-08-30T13:30:21.894094+01:00 Ubuntu-DevOps sshd[7078]: Failed password for leprecha from 127.0.0.1 port 40726 ssh2
2025-08-30T13:30:24.773226+01:00 Ubuntu-DevOps sshd[7078]: Accepted password for leprecha from 127.0.0.1 port 40726 ssh2
2025-08-30T13:32:55.538064+01:00 Ubuntu-DevOps sshd[7152]: Accepted password for leprecha from 127.0.0.1 port 50106 ssh2
```

`grep -rEn --color=always "$@" -e "$pattern" -- "$target"` — run `grep` recursively in that directory with these options:

- `r` → search recursively.
- `E` → use extended regex.
- `n` → show line numbers.
- `-color=always` → always highlight matches.
- `"$@"` → pass through any extra grep options the user provided.
- `e "$pattern"` → search pattern.
- `-- "$target"` → treat target as a filename (avoids issues if it starts with ).

---

**C) Nginx mini-report as a tool**

```bash
cat > tools/log-nginx-report.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
file="${1:-labs/lesson_08/logs/sample/nginx_access.log}"
[[ -r "$file" ]] || { echo "No such log: $file" >&2; exit 1; }
awk '{if (match($0, /"([A-Z]+) ([^"]+) HTTP\/[0-9.]+"/, m)) {
method=m[1]; path=m[2];
} else next;
status=$9; ip=$1; total++; codes[status]++; hits[path]++; ips[ip]++;
if (status ~ /^[45]/) errs++;
} END {
printf "Total: %d\n", total;
printf "Error rate (4xx+5xx): %.2f%%\n", (total?100*errs/total:0);
printf "Status codes: \n"; for (c in codes) printf "  %s: %d\n", c, codes[c];
printf "Top paths: \n"; for (p in hits) printf "  %s: %d\n", p, hits[p];
printf "Unique IPs: %d\n", length(ips)+0;
}' "$file"
SH

leprecha@Ubuntu-DevOps:~$ chmod +x tools/log-nginx-report.sh
leprecha@Ubuntu-DevOps:~$ ./tools/log-nginx-report.sh
Total: 4
Error rate (4xx+5xx): 50.00%
Status codes: 
  200: 2
  401: 1
  500: 1
Top paths: 
  /index.html: 1
  /api/v1/login: 1
  /api/v1/users: 2
Unique IPs: 3
```

`if (match($0, /"([A-Z]+) ([^"]+) HTTP\/[0-9.]+"/, m)) { method=m[1]; path=m[2];}` — uses a regex to capture HTTP request info like `"GET /path HTTP/1.1"`.

- `([A-Z]+)` → the HTTP method (GET/POST/…) → stored in `m[1]`.
- `([^"]+)` → the request path (up to the next quote) → stored in `m[2]`.

---

`if (status ~ /^[45]/) errs++` — If the status code starts with 4 or 5 → it’s an error → increment `errs`.

`printf "Error rate (4xx+5xx): %.2f%%\n", (total?100*errs/total:0);` — print error rate in percent: `(errs/total*100)` if `total > 0`, otherwise `0`. 

---

## Optional Hard

- `find … -print0 | xargs -0 grep -E …` across rotated logs.
- Pretty tables in `awk` (`printf` columns with widths, headers).
- Export CSV: `awk -F' ' '{print date,ip,status,path}' > report.csv` (adapt fields).
- Combine journal + file logs (`journalctl → grep → awk → tee`).

---

## Upgrade of tools (v2)

### **1) SSH-fails v2:**

- range (time range selection),
- log/journal source,
- rotations,
- IPv4/IPv6.

```bash
cat > tools/log-ssh-fail-report.v2.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
src="journal"
since="today"
top=10
all=0
usage(){ echo "Usage: $0 [--source journal|auth] [--since STR] [--top N] [--all]"; }
while [[ $# -gt 0 ]]; do
case "$1" in
--source) src="${2:-journal}"; shift 2;;
--since)  since="${2:-today}"; shift 2;;
--top)    top="${2:-10}"; shift 2;;
--all)    all=1; shift;;
-h|--help) usage; exit 0;;
*) usage; exit 1;;
esac
done
if [[ "$src" == "auth" ]]; then
pat='Failed password'
if (( all )); then
sudo zgrep -hE "$pat" /var/log/auth.log* 2>/dev/null || true
else
sudo grep -hE "$pat" /var/log/auth.log 2>/dev/null || true
fi
else
journalctl -u ssh --since "$since" -o cat | grep -E 'Failed password' || true
fi | awk '{
if (match($0, /([0-9]{1,3}\.){3}[0-9]{1,3}/, m)) { print m[0]; next }
if (match($0, /\b([0-9a-fA-F]{1,4}:){2,}[0-9a-fA-F]{1,4}\b/, m)) { print m[0]; next }
}' | sort | uniq -c | sort -nr | head -n "$top"
SH

leprecha@Ubuntu-DevOps:~$ chmod +x tools/log-ssh-fail-report.v2.sh
leprecha@Ubuntu-DevOps:~$ shellcheck ./tools/log-ssh-fail-report.v2.sh || true
leprecha@Ubuntu-DevOps:~$ ./tools/log-ssh-fail-report.v2.sh
     19 127.0.0.1
      1 0.0.0.0
leprecha@Ubuntu-DevOps:~$ ./tools/log-ssh-fail-report.v2.sh --source auth --all | head
      2 127.0.0.1
```

## Line-by-line

- Defaults: `src=journal`, `since=today`, `top=10`, `all=0`.
- Flags: `--source`, `--since`, `--top`, `--all`, `--help`.
- Source:
    - `auth`: grep `Failed password` in `/var/log/auth.log` (or all rotations with `zgrep` if `-all`).
    - `journal`: `journalctl -u ssh --since "$since" -o cat`.
- AWK: match then print the **first** IPv4- or IPv6-looking token from each line.
- Then `sort | uniq -c | sort -nr | head -n "$top"`.

---

### **2) log-grep v2:** filter by unit/journal tag and sshd-only

```bash
cat > tools/log-grep.v2.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
usage(){ echo "Usage: $0 <pattern> <file|dir|journal> [--unit UNIT] [--tag TAG] [--sshd-only] [-- <extra grep opts>]"; }
[[ $# -ge 2 ]] || { usage; exit 1; }
pat="$1"; target="$2"; shift 2
unit=""; tag=""; sshd_only=0
while [[ $# -gt 0 ]]; do
case "$1" in
--unit)      unit="${2:-}"; shift 2;;
--tag)       tag="${2:-}"; shift 2;;
--sshd-only) sshd_only=1; shift;;
--) shift; break;;
*) break;;
esac
done
if [[ "$target" == "journal" ]]; then
cmd=(journalctl -o cat --no-pager)
[[ -n "$unit" ]] && cmd+=(-u "$unit")
[[ -n "$tag"  ]] && cmd+=(-t "$tag")
"${cmd[@]}" | grep -nE "$@" -e "$pat" || true
else
if [[ -d "$target" ]]; then
grep -rEn "$@" -e "$pat" -- "$target" || true
else
grep -nE  "$@" -e "$pat" -- "$target" || true
fi
fi | { if (( sshd_only )); then grep -E 'sshd\[' || true; else cat; fi; }
SH

leprecha@Ubuntu-DevOps:~$ chmod +x tools/log-grep.v2.sh
leprecha@Ubuntu-DevOps:~$ tools/log-grep.v2.sh "Failed password" journal --tag sshd
4:Failed password for leprecha from 127.0.0.1 port 44752 ssh2
8:Failed password for leprecha from 127.0.0.1 port 40726 ssh2
leprecha@Ubuntu-DevOps:~$ tools/log-grep.v2.sh "Accepted" journal --unit ssh.service
7:Accepted password for leprecha from 127.0.0.1 port 44752 ssh2
11:Accepted password for leprecha from 127.0.0.1 port 40726 ssh2
13:Accepted password for leprecha from 127.0.0.1 port 50106 ssh2
15:Accepted publickey for leprecha from 127.0.0.1 port 37550 ssh2
17:Accepted publickey for leprecha from 127.0.0.1 port 47444 ssh2
```

## Line-by-line

- `[[ $# -ge 2 ]] || { usage; exit 1; }` — need at least `<pattern> <target>`.
- `while ... case ... esac` — parse options:
    - `--unit UNIT` → set journalctl unit filter.
    - `--tag TAG` → set journalctl syslog tag (e.g., `sshd`).
    - `--sshd-only` → later, keep only lines containing `sshd[`.
    - `-` → stop parsing; the rest goes straight to `grep` as extra options.
    
    ---
    
- `if [[ "$target" == "journal" ]]; then` — journal mode:
    - `cmd=(journalctl -o cat --no-pager)` — build base journalctl command (raw output, no pager).
    - `[[ -n "$unit" ]] && cmd+=(-u "$unit")` — add unit filter if given.
    - `[[ -n "$tag" ]] && cmd+=(-t "$tag")` — add tag filter if given.
    - `"${cmd[@]}" | grep -nE "$@" -e "$pat" || true` — run journalctl, pipe to `grep` with line numbers; pass any extra grep flags after `-`.
    
    ---
    
- `grep -rEn "$@" -e "$pat" -- "$target" || true` — recursive grep with line numbers; extras go to grep; `-` ends option parsing.
- `grep -nE "$@" -e "$pat" -- "$target" || true` — grep that file.

---

- `| { if (( sshd_only )); then grep -E 'sshd\[' || true; else cat; fi; }`
    - If `-sshd-only` was set, post-filter to lines containing `sshd[`; otherwise pass through.

---

## Artifacts

- `labs/lesson_08/mock/sshd_config`
- `labs/lesson_08/logs/sample/nginx_access.log`
- `tools/log-ssh-fail-report.sh`
- `tools/log-ssh-fail-report.v2.sh`
- `tools/log-grep.sh`
- `tools/log-grep.v2.sh`
- `tools/log-nginx-report.sh`

---

## Notes

- Practice on **copies** of system configs; use `sed -ri.bak` for safe in-place edits.
- Prefer `grep -E` (extended regex); handy flags: `-n` (lines), `-i` (case), `-v` (invert), `-r` (recursive).
- `journalctl -o cat` pairs well with grep/awk; default to `-u ssh` for unit-scoped queries (use `-t sshd` as needed).
- AWK: associative arrays initialize on first use (`counts[key]++`); print summaries in `END { … }`.
- Rotated logs: include `.1`/`.gz` with `zgrep -h`.

---

## Summary

- Practiced **log triage** with `grep` on auth/journal sources.
- Used **sed** safely on a **mock** `sshd_config` copy (`-ri.bak`) and verified with `diff`.
- Built compact **awk** reports (totals, status groups, top paths/IPs).
- Wrapped pipelines into reusable tools: `log-ssh-fail-report.sh` (and v2 with journal/auth/rotations),
`log-grep.sh` (and v2 with unit/tag filters), `log-nginx-report.sh`.

**Key takeaways:** fast pipelines (`journalctl | grep -E | awk | sort | uniq -c`), safe edits, reusable CLI tools.

**Next steps:** CSV export with `awk`, large-scale rotations via `find … -print0 | xargs -0`, scheduling via cron/systemd timers.

---

## To repeat

- `grep -nEi`, `grep -rE`, negate with `-v`; combine with journal: `journalctl -u ssh -o cat | grep -E "pat"`.
- `sed -ri.bak 's/^#?Key\\s+.*/Key value/' file` (in-place with backup).
- `awk '{…} END {…}'` with counters/maps; top-lists via `sort -nr | head`.
- Rotations: `zgrep -hE "Failed password" /var/log/auth.log* | awk '…' | sort | uniq -c | sort -nr | head`.