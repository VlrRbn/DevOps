# lesson_01

# Environment Setup and Basic Linux Commands

---

**Date: 2025-08-19**

**Topic:** Environment Setup.

**Daily goal:** Prepare environment for Linux learning.

---

## 1. Learned Material

**Commands and what they do:**

 `pwd` — Show path to current directory.

```bash
leprecha@Ubuntu-DevOps:~$ pwd
/home/leprecha
```

`pwd` In Linux, this is a command that shows the current working directory.
 (*print working directory*)

---

`ls -la` — list all files (including hidden) with details.

`-l` long format; `-a` show hidden.

```bash
leprecha@Ubuntu-DevOps:~$ ls -la
-rw-------  1 leprecha sysadmin 2791 Aug 19 15:54 .bash_history
drwxr-xr-x  2 leprecha sysadmin 4096 Aug 19 15:19 Desktop
```

1. - rw - - - - - - - — access permissions (d = directory, - = file).
2. 1 — Number of hard link.
3. leprecha — file owner.
4. sysadmin — group.
5. 2791 — size in bytes.
6. Aug 19 16:04 — date of last modification.
7. .bash_history — file or directory name.

---

`cd /etc` — change directory.

```bash
leprecha@Ubuntu-DevOps:~$ cd /etc
leprecha@Ubuntu-DevOps:/etc$ 
```

---

`mkdir demo` — create directory named demo.

- `mkdir` — *make directory*.
- `demo` — name of the new folder.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir demo
drwxrwxr-x  2 leprecha sysadmin 4096 Aug 19 16:32 demo
```

---

`touch demo/file.txt`— create empty file (or update mtime).

```bash
leprecha@Ubuntu-DevOps:~$ touch demo/file.txt
leprecha@Ubuntu-DevOps:~$ ls -la demo
drwxrwxr-x  2 leprecha sysadmin 4096 Aug 19 16:34 .
drwxr-x--- 18 leprecha sysadmin 4096 Aug 19 16:32 ..
-rw-rw-r--  1 leprecha sysadmin    0 Aug 19 16:34 file.txt
```

- `touch` — creates an empty file if it does not exist.
- `demo/file.txt` — the path where this file will be created.

---

`cp demo/file.txt demo/file.bak` — copy file.

```bash
leprecha@Ubuntu-DevOps:~$ cp demo/file.txt demo/file.bak
leprecha@Ubuntu-DevOps:~$ ls -la demo
-rw-r--r--  1 leprecha sysadmin    0 Aug 19 16:46 file.bak
-rw-rw-r--  1 leprecha sysadmin    0 Aug 19 16:34 file.txt
```

- `cp` — *copy*.
- The first argument is what we copy.
- The second is where we copy it to.

---

`mv demo/file.bak demo/file.old` — rename/move.

```bash
leprecha@Ubuntu-DevOps:~$ mv demo/file.bak demo/file.old
leprecha@Ubuntu-DevOps:~$ ls -la demo
drwxrwxr-x  2 leprecha sysadmin 4096 Aug 19 16:54 .
drwxr-x--- 18 leprecha sysadmin 4096 Aug 19 16:32 ..
-rw-r--r--  1 leprecha sysadmin    0 Aug 19 16:46 file.old
-rw-rw-r--  1 leprecha sysadmin    0 Aug 19 16:34 file.txt
```

- `mv` — *move*, but if the path stays the same, it’s just a rename.
- The first argument is what we move/rename.
- The second is the new name or path.

---

`rm demo/file.old` — remove file.

```bash
leprecha@Ubuntu-DevOps:~$ rm demo/file.old
leprecha@Ubuntu-DevOps:~$ ls -la demo
drwxrwxr-x  2 leprecha sysadmin 4096 Aug 19 16:58 .
drwxr-x--- 18 leprecha sysadmin 4096 Aug 19 16:32 ..
-rw-rw-r--  1 leprecha sysadmin    0 Aug 19 16:34 file.txt
```

- **`rm`** — removes a file.
- `rm -r` — removes a directory and everything inside it.
- `rm -ri` — (`-i` = interactive → asks before deleting each file).

---

`man ls` — open manual page for ls.

---

`whoami` — shows which user I am currently logged in the system.

```bash
leprecha@Ubuntu-DevOps:~$ whoami
leprecha
```

---

`hostname` — system hostname.

```bash
leprecha@Ubuntu-DevOps:~$ hostname
Ubuntu-DevOps
```

---

`date` — current date and time in the system.

```bash
leprecha@Ubuntu-DevOps:~$ date
Tue Aug 19 09:04:25 PM IST 2025
```

---

`clear` — clears the terminal screen, removing all previous output.

---

`uname -a` — kernel/system info.

```bash
leprecha@Ubuntu-DevOps:~$ uname -a
Linux Ubuntu-DevOps 6.14.0-28-generic #28~24.04.1-Ubuntu SMP PREEMPT_DYNAMIC Fri Jul 25 10:47:01 UTC 2 x86_64 x86_64 x86_64 GNU/Linux
```

---

`exit` — closes the current terminal session (shell).

| Command | Description |
| --- | --- |
| `pwd` | Show path to current directory |
| `ls -la` | List all files (including hidden) with details |
| `cd` /etc | Change to `/etc` directory |
| `mkdir` demo | Create `demo` directory |
| `touch` demo/file.txt | Create empty file `file.txt` in `demo` |
| `cp` demo/file.txt demo/file.bak | Copy file with new name `file.bak` |
| `mv` demo/file.bak demo/file.old | Rename file |
| `rm` demo/file.old | Remove file |
| `man` `ls` | Open manual page for `ls` |
| `whoami` | Show current username |
| `hostname` | Show system hostname |
| `date` | Show current date and time |
| `clear` | Clear terminal screen |
| `uname -a` | Show system and kernel info |
| `exit` | Exit terminal or session |

---

## 2. Working with nano and the Filesystem.

- Create `hello.txt` and edit in nano.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir -p ~/practice
leprecha@Ubuntu-DevOps:~$ cd ~/practice
leprecha@Ubuntu-DevOps:~/practice$ nano hello.txt
# write “Hello world!”, Ctrl+O, Enter, Ctrl+X
leprecha@Ubuntu-DevOps:~/practice$ cat hello.txt
Hello world!
```

1. Create a test folder — mkdir practice.
2. Go to the folder cd practice.
3. Create and open the file hello.txt, then write a greeting, save with **Ctrl+O**, and close with **Ctrl+X**.
4. Check the contents of the file using cat hello.txt.

---

### Practice copying, renaming, and deleting files.

Copying (cp).

```bash
leprecha@Ubuntu-DevOps:~/practice$ cp hello.txt hello_new.txt
leprecha@Ubuntu-DevOps:~/practice$ ls -l
drwxr-xr-x  2 leprecha sysadmin 4096 Aug 19 21:13 .
drwxr-x--- 19 leprecha sysadmin 4096 Aug 19 21:08 ..
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:13 hello_new.txt
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:08 hello.txt
```

Copy hello.txt in hello_new.txt.

---

Renaming (mv).

```bash
leprecha@Ubuntu-DevOps:~/practice$ mv hello_new.txt renamed.txt
leprecha@Ubuntu-DevOps:~/practice$ ls -la
drwxr-xr-x  2 leprecha sysadmin 4096 Aug 19 21:14 .
drwxr-x--- 19 leprecha sysadmin 4096 Aug 19 21:08 ..
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:08 hello.txt
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:13 renamed.txt
```

Renaming hello_new.txt in renamed.txt.

---

Deleting (rm).

```bash
leprecha@Ubuntu-DevOps:~/practice$ rm hello.txt
leprecha@Ubuntu-DevOps:~/practice$ ls -la
drwxr-xr-x  2 leprecha sysadmin 4096 Aug 19 21:15 .
drwxr-x--- 19 leprecha sysadmin 4096 Aug 19 21:08 ..
-rw-r--r--  1 leprecha sysadmin   13 Aug 19 21:13 renamed.txt
```

Deleting file hello.txt.

---

### Learn basic FHS structure (`/etc`, `/var`, `/usr`, `/home`).

## **`/etc`**

System and service configuration files.

Contains settings for everything: network (`hosts`, `hostname`), users (`passwd`, `shadow`), services (`ssh/sshd_config`, `cron.d`).

---

## **`/var`**

Variable data that changes frequently. Logs, queues, databases, caches.

Examples:

- `/var/log` — system and application logs.
- `/var/spool` — job queues (printing, mail).
- `/var/cache` — program caches.

---

## **`/usr`**

Programs and files installed for all users.

- `/usr/bin` — executables (commands).
- `/usr/lib` — libraries.
- `/usr/share` — shared data (icons, docs).

---

## **`/home`**

User home directories. Each contains personal files, settings, and work data.

Example: `/home/sysadmin`

/                  -> System root
├─ etc/            -> System & service configs
│  ├─ hosts        -> Local DNS
│  ├─ passwd       -> Users
│  └─ ssh/         -> SSH settings
├─ var/            -> Variable data (logs, caches, queues)
│  ├─ log/         -> Logs
│  ├─ cache/       -> Caches
│  └─ spool/       -> Job queues
├─ usr/            -> Programs & libraries
│  ├─ bin/         -> Executables
│  ├─ lib/         -> Libraries
│  └─ share/       -> Shared data
├─ home/           -> User home dirs
│  └─ youruser/    -> Personal files
├─ tmp/            -> Temporary files
├─ bin/, sbin/     -> Essential utilities
└─ root/           -> Root’s home

Remember:

- `/etc` — settings.
- `/var` — frequently changing data.
- `/usr` — programs.
- `/home` — personal data.

---

## 3. Practice

1. Creating directory structure.
- Create a folder `projects` with three subfolders: `scripts`, `configs`, `logs`.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir -p ~/projects/{scripts,configs,logs}
leprecha@Ubuntu-DevOps:~$ cd projects
leprecha@Ubuntu-DevOps:~/projects$ ls -la
total 12
4 drwxr-xr-x 2 leprecha sysadmin 4096 Aug 19 21:22 configs
4 drwxr-xr-x 2 leprecha sysadmin 4096 Aug 19 21:22 logs
4 drwxr-xr-x 2 leprecha sysadmin 4096 Aug 19 21:22 scripts
```

---

`mkdir -p ~/projects/{scripts,configs,logs}`  - create folder `projects` with three subfolders: `scripts`, `configs`, `logs`.

- `mkdir` — create a directory.
- `-p` — create all missing parent directories.
- **`~`** — my home directory (`/home/my_name`).
- `projects/{scripts,configs,logs}` — Brace expansion in bash will create three subfolders `scripts,configs,logs`**.**

---

2. Working with files.

- Create two empty files in `configs`, add text to `startup.log`.

```bash
leprecha@Ubuntu-DevOps:~$ touch ~/projects/configs/{nginx.conf,ssh_config}
leprecha@Ubuntu-DevOps:~$ cd projects/configs
leprecha@Ubuntu-DevOps:~/projects/configs$ ls -la
total 0
0 -rw-r--r-- 1 leprecha sysadmin 0 Aug 19 21:26 nginx.conf
0 -rw-r--r-- 1 leprecha sysadmin 0 Aug 19 21:26 ssh_config
```

`touch ~/projects/configs/{nginx.conf,ssh_config}`

- `touch` — creates empty files (or updates the modification time).
- `~/projects/configs/` — path to `configs` in home directory.
- `{nginx.conf,ssh_config}` — brace expansion creates two files at once.

```bash
leprecha@Ubuntu-DevOps:~$ echo "Hello DevOps" > ~/projects/logs/startup.log
leprecha@Ubuntu-DevOps:~$ cd projects/logs
leprecha@Ubuntu-DevOps:~/projects/logs$ cat startup.log
Hello DevOps
```

`echo "Hello DevOps" > ~/projects/logs/startup.log`

- `echo` — prints text or the value of a variable to the terminal.
- `>` — redirects output into a file, overwriting it.
- `>>` — redirects output to the end of a file.
- `cat` — prints the contents of a file to the terminal.

---

3. Copying and backups.

- Make a copy of `startup.log`.

```bash
leprecha@Ubuntu-DevOps:~$ cp ~/projects/logs/startup.log ~/projects/logs/startup.log.bak
leprecha@Ubuntu-DevOps:~$ cd projects/logs
leprecha@Ubuntu-DevOps:~/projects/logs$ ls -la
total 8
4 -rw-r--r-- 1 leprecha sysadmin 13 Aug 19 21:28 startup.log
4 -rw-r--r-- 1 leprecha sysadmin 13 Aug 19 21:36 startup.log.bak
```

`cp ~/projects/logs/startup.log ~/projects/logs/startup.log.bak`

- `cp` — copy files and directories.
- The first argument is the source file (`startup.log`).
- The second is the new file (`startup.log.bak`).

**Common options:**

- `-r` (or `-recursive`) — copy directories recursively.
- `-i` (or `-interactive`) — ask before overwriting.
- `-v` (or `-verbose`) — show what is being copied.

---

4. Searching files.

- Find all `.conf` files in `projects`.

```bash
leprecha@Ubuntu-DevOps:~$ find ~/projects -name "*.conf"
/home/leprecha/projects/configs/nginx.conf
```

`find ~/projects -name "*.conf"`

- `find` — searches for files and directories.
- `~/projects` — where to search (here it’s your `projects` directory).
- `name "*.conf"` — condition: the file name must end with `.conf`.
    - — any sequence of characters.
    - `.conf` — the file extension itself.

---

5. Permissions.

- Give the file owner read/write permissions only for `ssh_config`.

```bash
leprecha@Ubuntu-DevOps:~$ chmod 600 ~/projects/configs/ssh_config
```

`chmod 600 ~/projects/configs/ssh_config`

- `chmod` — *change mode*, modifies file permissions.
- `600` — octal representation of permissions:
    - `6` — `rw-` (read + write) for the owner.
    - `0` — `--` (no access) for the group.
    - `0` — `--` (no access) for others.

`ls -l ~/projects/configs/ssh_config` - example output.

```bash
leprecha@Ubuntu-DevOps:~$ ls -l ~/projects/configs/ssh_config
-rw------- 1 leprecha sysadmin 0 Aug 19 21:26 /home/leprecha/projects/configs/ssh_config
```

- `rw-------` — file permissions.
- `1` — number of links.
- `leprecha` — owner of the file.
- `sysadmin` — owner’s group.
- `0` — file size in bytes.
- `Aug 19 21:26` — last modification date.
- `ssh_config` — file name.
- `ls -R ~/projects` — shows all contents of the `projects` directory recursively.

---

## 4. Daily Summary

- **Learned:** Basic Linux commands, nano, FHS
- **Hard:** —
- **Repeat:** Permissions (`chmod`, modes)
- **Idea:** Script to bootstrap a project tree