# 00 Foundations Bridge (After Lessons 1-4)

**Purpose:** Close practical gaps before continuing deeper Linux lessons.

This file does not replace lessons 1-4.  
It is a compact add-on with topics that are often assumed later.

---

## 1. I/O Basics: stdin, stdout, stderr, redirects, pipes

### What

- `stdout` (fd `1`) - normal output
- `stderr` (fd `2`) - error output
- `stdin` (fd `0`) - input stream

### Why

Without redirection and pipes, admin work and scripting become slow/manual.

### Minimal commands

```bash
echo "ok" > out.txt
echo "one more" >> out.txt
ls /not-exists 2> err.txt
ls /not-exists > all.txt 2>&1
cat out.txt | wc -l
```

### Mini-practice

```bash
mkdir -p ~/bridge/io && cd ~/bridge/io
echo "line1" > app.log
echo "line2" >> app.log
ls /tmp /nope > scan.txt 2> scan.err
cat scan.txt scan.err > scan.all
wc -l scan.all
```

---

## 2. Search + filter: `find` and `grep`

### What

- `find` searches files/directories
- `grep` searches text patterns

### Why

These two commands are the standard way to locate files and inspect logs/configs.

### Minimal commands

```bash
find ~/bridge -type f -name "*.log"
grep -n "line2" ~/bridge/io/app.log
grep -R --line-number "PermitRootLogin" /etc/ssh 2>/dev/null
```

### Mini-practice

```bash
mkdir -p ~/bridge/search && cd ~/bridge/search
printf "alpha\nbeta\nerror: timeout\n" > app.log
printf "ok\nerror: denied\n" > worker.log
find . -type f -name "*.log"
grep -n "error" ./*.log
```

---

## 3. Links: symlink vs hardlink

### What

- hardlink: another name for same inode
- symlink: special file pointing to a path

### Why

Links are used in deployments, versioned configs, and filesystem organization.

### Minimal commands

```bash
echo "v1" > file.txt
ln file.txt file.hard
ln -s file.txt file.sym
ls -li file.txt file.hard file.sym
```

### Mini-practice

```bash
mkdir -p ~/bridge/links && cd ~/bridge/links
echo "hello" > original.txt
ln original.txt original.hard
ln -s original.txt original.sym
echo "world" >> original.hard
cat original.txt
cat original.sym
```

---

## 4. Archives: `tar`, `gzip`

### What

- `tar` packages files/directories
- `gzip` compresses data

### Why

Backups, artifact transfer, and log retention depend on archives.

### Minimal commands

```bash
tar -czf backup.tgz ~/bridge/io
tar -tf backup.tgz
mkdir -p /tmp/restore && tar -xzf backup.tgz -C /tmp/restore
```

### Mini-practice

```bash
mkdir -p ~/bridge/archive/src
echo "a" > ~/bridge/archive/src/a.txt
echo "b" > ~/bridge/archive/src/b.txt
tar -czf ~/bridge/archive/src.tgz -C ~/bridge/archive src
tar -tf ~/bridge/archive/src.tgz
```

---

## 5. Environment: variables, export, PATH, shell init

### What

- shell variables live in current shell
- exported vars are inherited by child processes
- `PATH` controls command lookup

### Why

Many tools/scripts fail due to missing env vars or wrong `PATH`.

### Minimal commands

```bash
MY_VAR="demo"
echo "$MY_VAR"
export APP_ENV=dev
env | grep "^APP_ENV="
echo "$PATH"
```

### Mini-practice

```bash
mkdir -p ~/bridge/env/bin
cat > ~/bridge/env/bin/hello-env <<'EOF'
#!/usr/bin/env bash
echo "APP_ENV=${APP_ENV:-unset}"
EOF
chmod +x ~/bridge/env/bin/hello-env
export PATH="$HOME/bridge/env/bin:$PATH"
export APP_ENV=lab
hello-env
```

---

## 6. Disk checks: `df`, `du`, `lsblk`

### What

- `df -h` - filesystem free/used space
- `du -sh` - directory size
- `lsblk` - block devices/partitions

### Why

Disk space is one of the most common production issues.

### Minimal commands

```bash
df -h
du -sh ~/bridge
lsblk
```

### Mini-practice

```bash
mkdir -p ~/bridge/space
dd if=/dev/zero of=~/bridge/space/blob.bin bs=1M count=20 status=none
du -sh ~/bridge/space
df -h ~
```
