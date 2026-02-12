# 05-07 Operations Bridge (After Lessons 5-7)

**Purpose:** Close practical gaps before continuing to text-processing and deeper automation lessons.

This file does not replace lessons 5-7.  
It is a compact add-on for concepts that are often assumed in later Linux/DevOps practice.

---

## 1. Script Execution Context: Shebang, PATH, `./`

### What

- Shebang (`#!/usr/bin/env bash`) chooses interpreter.
- Executable bit (`chmod +x`) allows direct run.
- `script.sh` and `./script.sh` are not always the same.

### Why

Many “No such file or directory” and “command not found” issues are path/context issues, not script logic bugs.

### Minimal commands

```bash
chmod +x ./my-script.sh
./my-script.sh

echo "$PATH"
command -v bash
```

### Mini-practice

```bash
mkdir -p ~/bridge57/bin
cat > ~/bridge57/bin/hello <<'EOF'
#!/usr/bin/env bash
echo "hello from script"
EOF
chmod +x ~/bridge57/bin/hello

# direct relative execution
~/bridge57/bin/hello

# add to PATH, then run by name
export PATH="$HOME/bridge57/bin:$PATH"
hello
```

---

## 2. Exit Codes and Flow Control (`&&`, `||`, `set -e`)

### What

- `0` means success; non-zero means failure.
- `cmd1 && cmd2` runs `cmd2` only if `cmd1` succeeded.
- `cmd1 || cmd2` runs `cmd2` only if `cmd1` failed.

### Why

Lessons 5-7 scripts depend on clear success/failure flow for safe operations.

### Minimal commands

```bash
true; echo $?
false; echo $?

mkdir -p /tmp/demo && echo "ok"
ls /not-here || echo "fallback"
```

### Mini-practice

```bash
file=/tmp/bridge57.txt
[[ -f "$file" ]] || echo "missing"

touch "$file"
[[ -f "$file" ]] && echo "exists"
```

---

## 3. Quoting, Word Splitting, and Arrays

### What

- Unquoted variables may split into multiple words.
- Quoted variables preserve exact value.
- Arrays are safest for dynamic command assembly.

### Why

File paths with spaces and optional arguments are common in ops scripts.

### Minimal commands

```bash
name="a_b.txt"
printf '%s\n' "$name"

cmd=(echo "file:$name")
"${cmd[@]}"
```

How to read this snippet:

- `printf` prints text using a format string.
- `%s` means: insert a string value.
- `\n` means: newline.
- `printf '%s\n' "$name"` prints `name` and then starts a new line.
- `cmd=(...)` builds a command as an array (separate elements, not one big string).
- `"${cmd[@]}"` executes that array safely, preserving spaces in arguments.

### Mini-practice

```bash
dir="/tmp/bridge_57"
mkdir -p "$dir"
: > "$dir/file_one.txt"

for f in "$dir"/*.txt; do
  printf 'found: %s\n' "$f"
done
```

---

## 4. Safe File Traversal: `find -print0`, `read -d ''`, `xargs -0`

### What

- NUL-delimited file streams are robust with special characters.
- `find ... -print0` pairs with `read -d ''` or `xargs -0`.

### Why

This prevents destructive bugs in bulk rename/backup/cleanup tasks.

### Minimal commands

```bash
find /tmp -maxdepth 1 -type f -name "*.log" -print0 |
  xargs -0 -r ls -l
```

### Mini-practice

```bash
mkdir -p "/tmp/bridge57_files"
: > "/tmp/bridge57_files/a_one.log"
: > "/tmp/bridge57_files/b_two.log"

find "/tmp/bridge57_files" -type f -name "*.log" -print0 |
  while IFS= read -r -d '' f; do
    printf '%s\n' "$f"
  done
```

---

## 5. Systemd/Journald Reading Basics for Automation

### What

- `systemctl status` gives state snapshot.
- `journalctl -u <unit>` gives unit-specific history.
- priorities map as `0..7` (`0=emerg`, `3=err`, `4=warning`, `6=info`).

### Why

Scripted troubleshooting is faster when you know exactly how to filter unit logs.

### Minimal commands

```bash
systemctl status cron --no-pager | sed -n '1,12p'
journalctl -u cron --since "30 min ago" -n 50 --no-pager
journalctl -u cron -p warning --since "1 hour ago" --no-pager
```

### Mini-practice

```bash
unit=cron
systemctl is-active "$unit"
journalctl -u "$unit" -n 20 --no-pager | tail -n 5
```

---

## 6. Package Safety Workflow (Simulation First)

### What

- `apt update` refreshes index.
- `apt-get -s upgrade` simulates normal upgrades.
- `apt-get -s full-upgrade` simulates upgrades that may add/remove packages.

### Why

Package operations are high-impact; simulation-first avoids surprise removals.

### Minimal commands

```bash
sudo apt update
sudo apt-get -s upgrade | sed -n '1,30p'
sudo apt-get -s full-upgrade | sed -n '1,30p'
```

### Mini-practice

```bash
apt-cache policy bash
apt-mark showhold
```

---

## 7. Restore Safety: Selections and Drift Control

### What

- package selection snapshot allows controlled restore
- restore should be simulated before apply

### Why

This reduces recovery time after bad upgrades or package drift.

### Minimal commands

```bash
dpkg --get-selections > packages.list
sudo dpkg --set-selections < packages.list
sudo apt-get -s dselect-upgrade | sed -n '1,30p'
```

### Mini-practice

```bash
mkdir -p ~/bridge57/state
dpkg --get-selections > ~/bridge57/state/packages.list
wc -l ~/bridge57/state/packages.list
```
