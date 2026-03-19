# lesson_01

# Linux Foundations: Environment, Commands, FHS, and Permissions

**Date:** 2025-08-19  
**Topic:** Environment setup  
**Daily goal:** Prepare the environment for Linux learning and practice basic file operations.
**Bridge:** [01-05 Foundations Bridge](../00-foundations-bridge/01-05-foundations-bridge.md) for missing basics after lessons 1-4.

---

## 1. Learned Material

### `pwd`

Shows the current working directory (`print working directory`).

```bash
leprecha@Ubuntu-DevOps:~$ pwd
/home/leprecha
```

---

### `ls -la`

Lists files in long format (`-l`) and includes hidden entries (`-a`).

```bash
leprecha@Ubuntu-DevOps:~$ ls -la
drwxr-x--- 18 leprecha sysadmin 4096 Aug 19 16:32 .
drwxr-xr-x  3 root     root     4096 Aug 19 15:19 ..
-rw-------  1 leprecha sysadmin 2791 Aug 19 15:54 .bash_history
drwxr-xr-x  2 leprecha sysadmin 4096 Aug 19 15:19 Desktop
```

How to read one line:

1. `-rw-------` - permissions (`d` means directory, `-` means regular file).
2. `1` - number of hard links.
3. `leprecha` - owner.
4. `sysadmin` - group.
5. `2791` - size in bytes.
6. `Aug 19 15:54` - last modification time.
7. `.bash_history` - file name.

---

### `cd /etc`

Changes the current directory.

```bash
leprecha@Ubuntu-DevOps:~$ cd /etc
leprecha@Ubuntu-DevOps:/etc$
```

---

### `mkdir demo`

Creates a directory named `demo`.

- `mkdir` - make directory.
- `demo` - new directory name.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir demo
leprecha@Ubuntu-DevOps:~$ ls -ld demo
drwxrwxr-x 2 leprecha sysadmin 4096 Aug 19 16:32 demo
```

---

### `touch demo/file.txt`

Creates an empty file if it does not exist, or updates file timestamp if it exists.

```bash
leprecha@Ubuntu-DevOps:~$ touch demo/file.txt
leprecha@Ubuntu-DevOps:~$ ls -la demo
drwxrwxr-x  2 leprecha sysadmin 4096 Aug 19 16:34 .
drwxr-x--- 18 leprecha sysadmin 4096 Aug 19 16:32 ..
-rw-rw-r--  1 leprecha sysadmin    0 Aug 19 16:34 file.txt
```

---

### `cp demo/file.txt demo/file.bak`

Copies a file.

- First argument: source.
- Second argument: destination.

```bash
leprecha@Ubuntu-DevOps:~$ cp demo/file.txt demo/file.bak
leprecha@Ubuntu-DevOps:~$ ls -la demo
-rw-r--r--  1 leprecha sysadmin    0 Aug 19 16:46 file.bak
-rw-rw-r--  1 leprecha sysadmin    0 Aug 19 16:34 file.txt
```

---

### `mv demo/file.bak demo/file.old`

Moves or renames a file.

- If path changes: move.
- If only file name changes in same path: rename.

```bash
leprecha@Ubuntu-DevOps:~$ mv demo/file.bak demo/file.old
leprecha@Ubuntu-DevOps:~$ ls -la demo
drwxrwxr-x  2 leprecha sysadmin 4096 Aug 19 16:54 .
drwxr-x--- 18 leprecha sysadmin 4096 Aug 19 16:32 ..
-rw-r--r--  1 leprecha sysadmin    0 Aug 19 16:46 file.old
-rw-rw-r--  1 leprecha sysadmin    0 Aug 19 16:34 file.txt
```

---

### `rm demo/file.old`

Removes a file.

- `rm` - remove file.
- `rm -r` - remove directory recursively.
- `rm -ri` - interactive recursive remove (asks before deletion).

```bash
leprecha@Ubuntu-DevOps:~$ rm demo/file.old
leprecha@Ubuntu-DevOps:~$ ls -la demo
drwxrwxr-x  2 leprecha sysadmin 4096 Aug 19 16:58 .
drwxr-x--- 18 leprecha sysadmin 4096 Aug 19 16:32 ..
-rw-rw-r--  1 leprecha sysadmin    0 Aug 19 16:34 file.txt
```

---

### `man ls`

Opens the manual page for `ls`.

---

### `whoami`

Shows the current user.

```bash
leprecha@Ubuntu-DevOps:~$ whoami
leprecha
```

---

### `hostname`

Shows system hostname.

```bash
leprecha@Ubuntu-DevOps:~$ hostname
Ubuntu-DevOps
```

---

### `date`

Shows current system date and time.

```bash
leprecha@Ubuntu-DevOps:~$ date
Tue Aug 19 09:04:25 PM IST 2025
```

---

### `clear`

Clears terminal screen.

---

### `uname -a`

Shows kernel and system information.

```bash
leprecha@Ubuntu-DevOps:~$ uname -a
Linux Ubuntu-DevOps 6.14.0-28-generic #28~24.04.1-Ubuntu SMP PREEMPT_DYNAMIC Fri Jul 25 10:47:01 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux
```

---

### `exit`

Closes current shell session.

### Quick command reference

| Command | Description |
| --- | --- |
| `pwd` | Show current directory path |
| `ls -la` | List files with details, including hidden files |
| `cd /etc` | Change to `/etc` directory |
| `mkdir demo` | Create `demo` directory |
| `touch demo/file.txt` | Create empty file |
| `cp demo/file.txt demo/file.bak` | Copy file |
| `mv demo/file.bak demo/file.old` | Rename or move file |
| `rm demo/file.old` | Remove file |
| `man ls` | Open manual page for `ls` |
| `whoami` | Show current username |
| `hostname` | Show hostname |
| `date` | Show date and time |
| `clear` | Clear terminal |
| `uname -a` | Show kernel/system info |
| `exit` | Exit shell |

---

## 2. Working with `nano` and the Filesystem

Create `hello.txt`, edit it in `nano`, save, and verify contents.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir -p ~/practice
leprecha@Ubuntu-DevOps:~$ cd ~/practice
leprecha@Ubuntu-DevOps:~/practice$ nano hello.txt
# type: Hello world!
# save: Ctrl+O, Enter
# exit: Ctrl+X
leprecha@Ubuntu-DevOps:~/practice$ cat hello.txt
Hello world!
```

Steps:

1. Create folder: `mkdir -p ~/practice`
2. Enter folder: `cd ~/practice`
3. Open and edit file: `nano hello.txt`
4. Check content: `cat hello.txt`

---

### Practice: copy, rename, delete

Copy:

```bash
leprecha@Ubuntu-DevOps:~/practice$ cp hello.txt hello_new.txt
leprecha@Ubuntu-DevOps:~/practice$ ls -la
drwxr-xr-x  2 leprecha sysadmin 4096 Aug 19 21:13 .
drwxr-x--- 19 leprecha sysadmin 4096 Aug 19 21:08 ..
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:08 hello.txt
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:13 hello_new.txt
```

Rename:

```bash
leprecha@Ubuntu-DevOps:~/practice$ mv hello_new.txt renamed.txt
leprecha@Ubuntu-DevOps:~/practice$ ls -la
drwxr-xr-x  2 leprecha sysadmin 4096 Aug 19 21:14 .
drwxr-x--- 19 leprecha sysadmin 4096 Aug 19 21:08 ..
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:08 hello.txt
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:13 renamed.txt
```

Delete:

```bash
leprecha@Ubuntu-DevOps:~/practice$ rm hello.txt
leprecha@Ubuntu-DevOps:~/practice$ ls -la
drwxr-xr-x  2 leprecha sysadmin 4096 Aug 19 21:15 .
drwxr-x--- 19 leprecha sysadmin 4096 Aug 19 21:08 ..
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:13 renamed.txt
```

---

## 3. Basic FHS Structure (`/etc`, `/var`, `/usr`, `/home`)

### `/etc`

System and service configuration files.

Examples:

- `/etc/hosts` - local hostname/IP mapping
- `/etc/passwd` - user account list
- `/etc/ssh/sshd_config` - SSH server configuration

### `/var`

Variable data that changes often.

- `/var/log` - logs
- `/var/cache` - application cache
- `/var/spool` - queued tasks (mail, print jobs, etc.)

### `/usr`

Installed user-space software and shared resources.

- `/usr/bin` - executable commands
- `/usr/lib` - libraries
- `/usr/share` - shared data and docs

### `/home`

User home directories with personal files and settings.

Example: `/home/leprecha`

```text
/                  -> filesystem root
├─ etc/            -> system and service configs
├─ var/            -> variable data (logs, cache, queues)
├─ usr/            -> applications, libraries, shared data
├─ home/           -> user home directories
├─ tmp/            -> temporary files
├─ bin/, sbin/     -> essential commands
└─ root/           -> root user home
```

Remember:

- `/etc` - settings
- `/var` - frequently changing data
- `/usr` - programs and shared resources
- `/home` - personal user data

---

## 4. Practice

### 1. Create directory structure

Task: create `projects` with subdirectories `scripts`, `configs`, `logs`.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir -p ~/projects/{scripts,configs,logs}
leprecha@Ubuntu-DevOps:~$ cd ~/projects
leprecha@Ubuntu-DevOps:~/projects$ ls -la
drwxr-xr-x 2 leprecha sysadmin 4096 Aug 19 21:22 configs
drwxr-xr-x 2 leprecha sysadmin 4096 Aug 19 21:22 logs
drwxr-xr-x 2 leprecha sysadmin 4096 Aug 19 21:22 scripts
```

Command breakdown:

- `mkdir` - create directory
- `-p` - create missing parent directories if needed
- `~` - home directory (`/home/<user>`)
- `{scripts,configs,logs}` - brace expansion to create multiple folders

---

### 2. Work with files

Task: create two config files and write a startup message to a log file.

```bash
leprecha@Ubuntu-DevOps:~$ touch ~/projects/configs/{nginx.conf,ssh_config}
leprecha@Ubuntu-DevOps:~$ ls -la ~/projects/configs
-rw-r--r-- 1 leprecha sysadmin 0 Aug 19 21:26 nginx.conf
-rw-r--r-- 1 leprecha sysadmin 0 Aug 19 21:26 ssh_config
```

```bash
leprecha@Ubuntu-DevOps:~$ echo "Hello DevOps" > ~/projects/logs/startup.log
leprecha@Ubuntu-DevOps:~$ cat ~/projects/logs/startup.log
Hello DevOps
```

Notes:

- `touch` - creates empty files or updates timestamp
- `>` - overwrite file with redirected output
- `>>` - append output to end of file
- `cat` - print file contents

---

### 3. Copy and backup

Task: create a backup of `startup.log`.

```bash
leprecha@Ubuntu-DevOps:~$ cp ~/projects/logs/startup.log ~/projects/logs/startup.log.bak
leprecha@Ubuntu-DevOps:~$ ls -la ~/projects/logs
-rw-r--r-- 1 leprecha sysadmin 13 Aug 19 21:28 startup.log
-rw-r--r-- 1 leprecha sysadmin 13 Aug 19 21:36 startup.log.bak
```

Useful `cp` options:

- `-r` - copy directories recursively
- `-i` - ask before overwrite
- `-v` - verbose output

---

### 4. Search files

Task: find all `.conf` files in `~/projects`.

```bash
leprecha@Ubuntu-DevOps:~$ find ~/projects -name "*.conf"
/home/leprecha/projects/configs/nginx.conf
```

Command breakdown:

- `find` - search files and directories
- `~/projects` - search path
- `-name "*.conf"` - match names ending in `.conf`

---

### 5. Permissions

Task: set permissions for `ssh_config` so only owner can read and write.

```bash
leprecha@Ubuntu-DevOps:~$ chmod 600 ~/projects/configs/ssh_config
leprecha@Ubuntu-DevOps:~$ ls -l ~/projects/configs/ssh_config
-rw------- 1 leprecha sysadmin 0 Aug 19 21:26 /home/leprecha/projects/configs/ssh_config
```

Explanation:

- `chmod` - change file permissions
- `600`:
  - owner: `rw-` (`6`)
  - group: `---` (`0`)
  - others: `---` (`0`)

Extra check:

```bash
leprecha@Ubuntu-DevOps:~$ ls -R ~/projects
```

---

## 5. Lesson Summary

- **What I learned:** navigation and file operations (`pwd`, `ls`, `cd`, `mkdir`, `touch`, `cp`, `mv`, `rm`), basic help tools (`man`), and system info commands (`whoami`, `hostname`, `date`, `uname -a`).
- **What I practiced:** created a real project structure (`~/projects/{scripts,configs,logs}`), created config files, wrote logs, created backups, searched files with `find`, and applied permissions with `chmod 600`.
- **Core concepts:** basic FHS map (`/etc`, `/var`, `/usr`, `/home`) and how to read `ls -l` output.
- **Needs repetition:** numeric permissions (`chmod` modes), safe deletion habits (`rm -i`), and faster reading of permission strings.
- **Next step:** write a small bootstrap script that creates the project tree and initial files automatically.
