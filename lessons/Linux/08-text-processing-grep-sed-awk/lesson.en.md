# lesson_08

# Text Processing for Ops: `grep`, `sed`, `awk`

**Date:** 2025-08-30  
**Topic:** Log filtering and parsing, safe config edits, mini reports, and reusable pipelines.  
**Daily goal:** Not just repeat commands, but understand why this command, this flag, and this step order.
**Bridge:** [08-11 Networking + Text Bridge](../00-foundations-bridge/08-11-networking-text-bridge.md) for deep explanations and troubleshooting across lessons 8-11.

---

## 1. Core Concepts

### 1.1 Pipeline model: what actually happens

A pipeline `A | B | C` is not “one command”, but three independent stages:

1. `A` produces a stream of lines to `stdout`.
2. `B` receives those lines from `stdin` and filters what matters.
3. `C` receives already filtered lines and builds an aggregate/report.

Mindset example:

- `journalctl -u ssh -o cat` -> source
- `grep -E 'Failed password|Accepted'` -> filter
- `awk '{...}'` -> structure-aware parsing

If the pipeline fails, debug in parts: first `A`, then `A|B`, then full `A|B|C`.

### 1.2 `grep`: where “search” ends and regex begins

`grep` answers: “Which lines match this pattern?”

- `-E`: enable extended regex (usually the practical default)
- `-n`: show line numbers
- `-i`: case-insensitive
- `-v`: show non-matching lines
- `-r`: recurse through a directory

Practical template:

```bash
grep -nE "pattern1|pattern2" file.log
```

When this is useful:

- in triage, start with a wider match set,
- then narrow patterns to remove noise.

### 1.3 `sed`: safe editing without risk

Use `sed` in two modes:

1. **preview** (`sed -n '1,80p' file`) to understand context,
2. **edit with backup** (`sed -ri.bak 's/.../.../' file`) for quick rollback.

Critical for training flow: edit config copies, not `/etc` directly.

### 1.4 `awk`: when you need it and when you do not

Use `awk` when you need to:

- extract concrete fields (`$1`, `$7`, `$9`),
- count grouped values (`codes[$9]++`),
- print final report in `END`.

Do not use `awk` when the task is only “find lines” — use `grep` there.

### 1.5 Log sources: file vs journal

- `auth.log` is convenient as a disk file, including rotations.
- `journalctl` is convenient for filtering by unit/tag/time window.

In practice, you want both paths in your toolbox.

### 1.6 Important exit-code detail (`grep`)

`grep` return codes:

- `0`: match found
- `1`: no matches (not always a business error)
- `2+`: execution/read error

That is why ops scripts sometimes use `|| true` after `grep`: to avoid crashing on expected “nothing found” cases.

### 1.7 Mini regex cheat sheet for this lesson

- `A|B` -> either `A` or `B`
- `^...` -> start of line
- `...$` -> end of line
- `\s+` -> one or more whitespace characters
- `#?` -> `#` may exist or not

Example from this lesson:

```bash
'^#?PasswordAuthentication\s+.+'
```

Reads as: line starts with optional `#`, then `PasswordAuthentication`, then spaces and a value.

---

## 2. Command Priority (What to Learn First)

### Core

- `grep -nE "..." <file>`
- `journalctl -u <unit> -o cat | grep -E ...`
- `sed -n 'start,endp' <file>`
- `sed -ri.bak 's/old/new/' <copy>`
- `awk '{print ...}' <file>`
- `awk` counters with `END`

### Optional

- `zgrep` on rotations
- `grep -rEn --include='*.log'`
- `sort | uniq -c | sort -nr`
- `tee` for view + save

### Advanced

- unified helper scripts (`log-grep.v2.sh`, `log-ssh-fail-report.v2.sh`)
- focused noise filtering
- stable repeatable reports

---

## 3. Core Commands with Breakdown: What / Why / When

### 3.1 SSH triage with `grep`

- **What:** search SSH auth events in `auth.log`.
- **Why:** quickly see failed and successful login attempts.
- **When:** first pass for access troubleshooting and baseline login audit.

```bash
sudo grep -nE "Failed password|Accepted password" /var/log/auth.log | head -n 20
```

Breakdown:

- `sudo` — file often requires elevated read access;
- `-nE` — line numbers + regex;
- `"Failed password|Accepted password"` — two event classes at once;
- `| head` — limit output volume.

### 3.2 Same triage via journal

- **What:** same triage, but from `journalctl` instead of file logs.
- **Why:** work in systemd log flow and avoid file-format dependency.
- **When:** on hosts where journal is the primary event source.

```bash
journalctl -u ssh --since "today" -o cat | grep -nE "Failed password|Accepted|Invalid user" | head -n 20
```

Breakdown:

- `-u ssh` — only SSH unit events;
- `--since "today"` — time constraint;
- `-o cat` — message-only output (less noise);
- then `grep` and `head` as in file flow.

### 3.3 Safe preview before edit

- **What:** read a file fragment without changes.
- **Why:** confirm context before editing.
- **When:** always before `sed -i` / `sed -ri.bak`.

```bash
sed -n '1,80p' labs/mock/sshd_config
```

### 3.4 Controlled key update

- **What:** in-place replacement of `PasswordAuthentication` with backup.
- **Why:** set target state in one regex and keep rollback ready.
- **When:** test edits on config copies and repeatable config changes.

```bash
sed -ri.bak 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication no/' labs/mock/sshd_config
```

Regex breakdown:

- `^` — line start,
- `#?` — optional comment marker,
- `PasswordAuthentication` — key name,
- `\s+` — one or more spaces,
- `.*` — current value,
- replacement to the target line.

Why this is practical:

- catches both commented and uncommented forms,
- converges to one clear target state,
- leaves backup (`.bak`).

### 3.5 Verify result and rollback path

- **What:** check changed line and diff before/after.
- **Why:** confirm only expected lines changed.
- **When:** immediately after any automated edit.

```bash
grep -nE '^#?PasswordAuthentication' labs/mock/sshd_config
diff -u labs/mock/sshd_config{.bak,} | sed -n '1,40p'
```

### 3.6 `awk` report for nginx access

- **What:** aggregate status/path/ip from access logs.
- **Why:** get mini report (total, status distribution, unique IPs) without external tools.
- **When:** service smoke-check, quick triage, post-change verification.

```bash
awk '{status=$9; path=$7; ip=$1; total++; codes[status]++; hits[path]++; ips[ip]++}
END {
  printf "Total: %d\n", total;
  for (c in codes) printf "code %s: %d\n", c, codes[c];
  printf "Unique IPs: %d\n", length(ips);
}' labs/logs/sample/nginx_access.log
```

Where `$1/$7/$9` come from:

- in typical nginx combined logs:
- `$1` = IP,
- `$7` = path (request part),
- `$9` = HTTP status.

What the logic does:

- `total++` — count all lines,
- `codes[status]++` — count statuses,
- `hits[path]++` — path popularity,
- `ips[ip]++` — IP set via array keys.

---

## 4. Optional: Commands with explanation

### 4.1 `zgrep -hE "Failed password" /var/log/auth.log*`

- **What:** search across `auth.log`, including rotations and `.gz`.
- **Why:** do not miss older events when current `auth.log` is small.
- **When:** investigation window is longer than one day.

```bash
sudo zgrep -hE "Failed password|Invalid user" /var/log/auth.log* | tail -n 30
```

### 4.2 `grep -rEn --include='*.log' ... <dir>`

- **What:** recursive search limited to selected file types.
- **Why:** avoid scanning everything and reduce noise.
- **When:** mixed directory content, but you only need logs.

```bash
grep -rEn --include='*.log' "error|fail|critical" ./labs
```

### 4.3 `sort | uniq -c | sort -nr`

- **What:** frequency counting pipeline.
- **Why:** quick “top list” without external language/database.
- **When:** need most frequent IP/path/status values.

```bash
journalctl -u ssh --since "today" -o cat |
grep -E "Failed password" |
awk '{for(i=1;i<=NF;i++) if($i=="from"){print $(i+1); break}}' |
sort | uniq -c | sort -nr | head -n 10
```

### 4.4 `awk -F` and `printf`

- **What:** explicit field separator and controlled output format.
- **Why:** make report output stable and readable.
- **When:** compare runs or paste results into notes/reports.

```bash
awk -F' ' '{printf "ip=%-15s status=%-3s path=%s\n", $1, $9, $7}' \
  labs/sample/nginx_access.log
```

### 4.5 `tee` for intermediate result capture

- **What:** duplicate stream to terminal and file.
- **Why:** preserve triage output artifact.
- **When:** incident investigation where you want saved evidence.

```bash
journalctl -u ssh --since "today" -o cat |
grep -E "Failed password|Accepted|Invalid user" |
tee /tmp/ssh_events_today.txt
```

---

## 5. Advanced: not just commands, but working tools

### 5.1 Why move commands into scripts

- ad-hoc command chains break easily on repetition;
- flags get forgotten;
- hard to hand over to another person.

A script locks interface and expected output.

### 5.2 `log-ssh-fail-report.v2.sh`

- **What:** report by IP from SSH fail events.
- **Why:** get top sources for selected period.
- **When:** brute-force triage, baseline security review.

Key flags:

- `--source journal|auth` source;
- `--since "today"` time window (for journal);
- `--top N` limit;
- `--all` include rotated auth logs.

```bash
./lessons/08-text-processing-grep-sed-awk/scripts/log-ssh-fail-report.v2.sh --source auth --all --top 20
```

### 5.3 `log-grep.v2.sh`

- **What:** unified grep interface for file/dir/journal.
- **Why:** avoid manual switching between different syntaxes.
- **When:** recurring triage across different data sources.

Key flags:

- `--unit` filter by unit in journal;
- `--tag` filter by tag;
- `--sshd-only` remove unrelated lines.

```bash
./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.v2.sh \
  "Failed password|Invalid user" journal --tag sshd --sshd-only
```

### 5.4 `log-nginx-report.sh`

- **What:** mini analytics on nginx access logs (total/error-rate/codes/top paths/unique IPs).
- **Why:** fast health snapshot.
- **When:** after deploy, smoke-check, short incident triage.

```bash
./lessons/08-text-processing-grep-sed-awk/scripts/log-nginx-report.sh \
  lessons/08-text-processing-grep-sed-awk/labs/sample/nginx_access.log
```

### 5.5 Practical advanced workflow

1. Build a source sample (`journalctl` or `auth.log*`).
2. Narrow noise with `grep`.
3. Aggregate via `awk`/`sort|uniq`.
4. Save output to file (`tee`).
5. If the command repeats, move it to `scripts/`.

---

## 6. Common mistakes (and quick fixes)

1. Mistake: “no output means command is broken”.  
Fact: maybe there are just no matches (`grep` returned `1`).

2. Mistake: immediately run `sed -i` on working config.  
Fix: start with a copy + `.bak`.

3. Mistake: too broad regex (`error|fail`) causing huge noise.  
Fix: start broad, then narrow by source and context.

4. Mistake: run long pipeline all at once without intermediate checks.  
Fix: validate stages separately (`A`, `A|B`, `A|B|C`).

---

## 7. Lesson Scripts

- `lessons/08-text-processing-grep-sed-awk/scripts/`
- `lessons/08-text-processing-grep-sed-awk/scripts/README.md`

Preparation:

```bash
chmod +x lessons/08-text-processing-grep-sed-awk/scripts/*.sh
```

---

## 8. Script walkthrough (what exactly we built)

### 8.1 `log-ssh-fail-report.sh`

- **What:** basic report by IP from SSH fail events.
- **Why:** quickly get top failed-login sources.
- **When:** quick triage without many flags.

How to read the logic:

1. `src="${1:-journal}"` — default source is journal.
2. If `auth` and `/var/log/auth.log` exists, read `auth.log*` via `zgrep`.
3. Otherwise read journal (`-t sshd`) and filter target lines.
4. `awk` extracts token after `from` (IP).
5. `sort | uniq -c | sort -nr | head` builds top list.

### 8.2 `log-ssh-fail-report.v2.sh`

- **What:** extended report (`--source`, `--since`, `--top`, `--all`).
- **Why:** control source, time window, and output volume.
- **When:** reusable investigation flow.

Key logic:

- `while/case` block parses flags;
- `--source auth` switches to file logs;
- `--all` includes rotations;
- `awk` extracts both IPv4 and IPv6;
- final pipeline counts frequency and sorts descending.

### 8.3 `log-grep.sh`

- **What:** basic helper for grep on file or directory.
- **Why:** single interface instead of manual choice between `grep -E` and `grep -rEn`.
- **When:** quick manual search in lab environment.

Logic:

- argument check (`<pattern> <file_or_dir>`);
- if target is directory -> recursive mode;
- if target is file -> regular mode with line numbers;
- `--` protects against paths starting with `-`.

### 8.4 `log-grep.v2.sh`

- **What:** extended helper for `file|dir|journal`.
- **Why:** same UX for different log sources.
- **When:** recurring ops triage where data is split between files and journal.

Key logic:

- `journal` mode builds `journalctl` command dynamically via array `cmd=(...)`;
- options `--unit` and `--tag` are appended only when provided;
- `--sshd-only` adds post-filter for lines containing `sshd[`;
- `--` forwards extra options directly to `grep`.

### 8.5 `log-nginx-report.sh`

- **What:** mini report for access logs (total, error rate, status codes, top paths, unique IPs).
- **Why:** quick traffic-state assessment without external analytics.
- **When:** post-deploy smoke-check, fast incident drill-down.

How to read awk block:

1. `match(...)` extracts method and path from `"GET /path HTTP/1.1"`.
2. Fields `$9`, `$7`, `$1` provide status, path, and IP.
3. Array counters accumulate aggregates.
4. `END` prints final summary including `4xx/5xx` error rate.

---

## 9. Mini-lab (Core Path)

```bash
mkdir -p labs/mock labs/logs/sample
cp /etc/ssh/sshd_config labs/mock/sshd_config 2>/dev/null || true

sudo grep -nE "Failed password|Accepted password" /var/log/auth.log | tail -n 20 || true
journalctl -u ssh --since "today" -o cat | grep -nE "Failed password|Accepted|Invalid user" | tail -n 20 || true

sed -ri.bak 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication no/' labs/mock/sshd_config
grep -nE '^#?PasswordAuthentication' labs/mock/sshd_config
diff -u labs/mock/sshd_config{.bak,} | sed -n '1,40p'

./lessons/08-text-processing-grep-sed-awk/scripts/log-nginx-report.sh
```

Understanding checks:

- can you explain every symbol in the `sed` regex;
- can you explain why awk uses `$1/$7/$9`;
- can you explain where file flow is better than journal flow, and vice versa.

---

## 10. Extended Lab (Advanced)

```bash
./lessons/08-text-processing-grep-sed-awk/scripts/log-ssh-fail-report.v2.sh --source journal --since "today" --top 10
./lessons/08-text-processing-grep-sed-awk/scripts/log-ssh-fail-report.v2.sh --source auth --all --top 10

./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.v2.sh "Failed password|Invalid user" journal --tag sshd
./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.v2.sh "Accepted" journal --unit ssh.service

./lessons/08-text-processing-grep-sed-awk/scripts/log-nginx-report.sh | tee /tmp/nginx_report.txt
```

---

## 11. Lesson Summary

- **What I learned:** practical Linux text-processing with `grep`, `sed`, `awk` and safe log pipelines.
- **What I practiced:** SSH-event filtering, config edits via `.bak`, mini nginx reports, and command packaging into scripts.
- **Advanced skills:** handling `file vs journal` source flows, regex noise control, and aggregation via `awk + sort + uniq`.
- **Operational focus:** work via safe flow `read -> filter -> aggregate -> save`, verify changes with `diff`, avoid blind `sed -i` on production files.
- **Repo artifacts:** `lessons/08-text-processing-grep-sed-awk/scripts/`, `lessons/08-text-processing-grep-sed-awk/scripts/README.md`.
