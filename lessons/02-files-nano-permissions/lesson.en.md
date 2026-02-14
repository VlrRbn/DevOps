# lesson_02

# Files, Nano, and Permissions in Linux

**Date:** 2025-08-20  
**Topic:** Working with files and permissions  
**Daily goal:** Reinforce file operations, practice `nano`, and understand permission and ownership basics.
**Bridge:** [01-05 Foundations Bridge](../00-foundations-bridge/01-05-foundations-bridge.md) for missing basics after lessons 1-4.

---

## 1. Review + New Commands

### `ls -la`

List directory contents in long format, including hidden files.

```bash
leprecha@Ubuntu-DevOps:~$ ls -la
drwxr-x--- 18 leprecha sysadmin 4096 Aug 20 17:07 .
drwxr-xr-x  3 root     root     4096 Aug 19 15:19 ..
-rw-------  1 leprecha sysadmin 8217 Aug 20 17:07 .bash_history
```

Flags:

- `-l` - long format
- `-a` - include hidden files

---

### `cd`

Change current directory.

```bash
leprecha@Ubuntu-DevOps:~$ cd /etc
leprecha@Ubuntu-DevOps:/etc$
```

---

### `pwd`

Print current working directory.

```bash
leprecha@Ubuntu-DevOps:~$ pwd
/home/leprecha
```

---

### `tree` (optional utility)

Show directory structure as a tree.

```bash
leprecha@Ubuntu-DevOps:~$ tree /etc | head -n 5
/etc
|-- adduser.conf
|-- alsa
|   `-- conf.d
|       `-- 10-rate-lav.conf -> /usr/share/alsa/alsa.conf.d/10-rate-lav.conf
```

If `tree` is not installed, use:

```bash
leprecha@Ubuntu-DevOps:~$ find /etc -maxdepth 2 | head -n 10
```

---

### `stat`

Show detailed metadata for a file.

```bash
leprecha@Ubuntu-DevOps:~$ stat /etc/passwd
  File: /etc/passwd
  Size: 2959       Blocks: 8          IO Block: 4096 regular file
Device: 259,2      Inode: 5507826     Links: 1
Access: (0644/-rw-r--r--)  Uid: (0/root)  Gid: (0/root)
Access: 2025-08-20 16:58:14.464296261 +0100
Modify: 2025-08-19 15:51:08.037927698 +0100
Change: 2025-08-19 15:51:08.038485928 +0100
 Birth: 2025-08-19 15:51:08.037485933 +0100
```

---

## 2. Working with Nano

`nano` is a simple terminal text editor for quick file editing.

Open or create file:

```bash
leprecha@Ubuntu-DevOps:~$ nano filename.txt
```

Useful keys:

| Key | Action |
| --- | --- |
| `Ctrl + O` | Save file |
| `Ctrl + X` | Exit nano |
| `Ctrl + G` | Help |
| `Ctrl + W` | Search |
| `Ctrl + K` | Cut line |
| `Ctrl + U` | Paste line |
| `Ctrl + C` | Cursor position |
| `Ctrl + _` | Go to line/column |

### Practice

1. Create `filename.txt` in home directory.
2. Write 2-3 English sentences about yourself.
3. Save and exit.
4. Copy file to `/tmp`.
5. Verify content with `cat`.

```bash
leprecha@Ubuntu-DevOps:~$ nano filename.txt
leprecha@Ubuntu-DevOps:~$ cp filename.txt /tmp/filename.txt
leprecha@Ubuntu-DevOps:~$ cat /tmp/filename.txt
How are you today? I am fine.
```

---

## 3. Copying, Moving, and Removing

| Command | Description |
| --- | --- |
| `cp file.txt backup.txt` | Copy file to new file |
| `cp file.txt /home/user/` | Copy file to directory |
| `cp -r myfolder /home/user/` | Copy directory recursively |
| `mv file.txt /home/user/` | Move file |
| `mv old.txt new.txt` | Rename file |
| `rm file.txt` | Remove file |
| `rm file1 file2` | Remove multiple files |
| `rm -r myfolder` | Remove directory recursively |
| `rm -rf myfolder` | Force-remove directory (dangerous) |

### Copying (`cp`)

```bash
leprecha@Ubuntu-DevOps:~$ cp filename.txt backup.txt
leprecha@Ubuntu-DevOps:~$ cat backup.txt
How are you today? I am fine.
```

Copy directory with content:

```bash
leprecha@Ubuntu-DevOps:~$ cp -r Folder /home/leprecha/Documents/
```

### Moving and renaming (`mv`)

```bash
leprecha@Ubuntu-DevOps:~$ mv filename.txt /home/leprecha/Documents/Folder/
leprecha@Ubuntu-DevOps:~$ mv /home/leprecha/Documents/Folder/filename.txt /home/leprecha/Documents/Folder/newfile.txt
```

### Removing (`rm`)

```bash
leprecha@Ubuntu-DevOps:~$ rm newfile.txt
leprecha@Ubuntu-DevOps:~$ rm backup.txt file.txt
```

Dangerous command:

```bash
leprecha@Ubuntu-DevOps:~$ rm -rf /home/leprecha/Music/Folder/
```

Notes:

- `-r` - remove recursively
- `-f` - force, no prompts
- `rm` has no real dry-run mode

Safer usage:

```bash
leprecha@Ubuntu-DevOps:~$ rm -ri /home/leprecha/Music/Folder/
leprecha@Ubuntu-DevOps:~$ rm -I /home/leprecha/Music/Folder/
```

If you need preview before deletion:

```bash
leprecha@Ubuntu-DevOps:~$ find /home/leprecha/Music/Folder -maxdepth 2 -print
```

### Practice

1. Create `~/lab2_files`.
2. Create `file1.txt`, `file2.txt`, `file3.txt`.
3. Copy `file1.txt` to `/tmp`.
4. Move `file2.txt` to `/tmp/file2_moved.txt`.
5. Delete `file3.txt`.
6. Remove `~/lab2_files`.

```bash
leprecha@Ubuntu-DevOps:~$ mkdir ~/lab2_files
leprecha@Ubuntu-DevOps:~$ touch ~/lab2_files/file1.txt ~/lab2_files/file2.txt ~/lab2_files/file3.txt
leprecha@Ubuntu-DevOps:~$ cp ~/lab2_files/file1.txt /tmp/
leprecha@Ubuntu-DevOps:~$ mv ~/lab2_files/file2.txt /tmp/file2_moved.txt
leprecha@Ubuntu-DevOps:~$ rm ~/lab2_files/file3.txt
leprecha@Ubuntu-DevOps:~$ rm -r ~/lab2_files
```

---

## 4. Permissions and Ownership

Linux permissions define who can access a file or directory.

Permission groups:

1. Owner (`u`)
2. Group (`g`)
3. Others (`o`)

Permission bits:

- `r` - read
- `w` - write
- `x` - execute (for directories: traverse/enter)

### Read `ls -l` output

```bash
leprecha@Ubuntu-DevOps:~$ ls -l
drwxr-xr-x 2 leprecha sysadmin 4096 Aug 20 17:23 Desktop
drwx------ 6 leprecha sysadmin 4096 Aug 19 21:00 snap
-rw-rw-r-- 1 leprecha sysadmin  492 Aug 20 19:31 learnlinux.spec
```

Example breakdown for `-rw-rw-r--`:

- first char `-` = regular file
- owner `rw-`
- group `rw-`
- others `r--`

### Change permissions with `chmod`

Symbolic mode:

- `chmod u+x file` - add execute for owner
- `chmod g-w file` - remove write from group
- `chmod o+r file` - add read for others

Numeric mode:

- `r = 4`, `w = 2`, `x = 1`
- `7 = rwx`, `6 = rw-`, `5 = r-x`, `4 = r--`

Examples:

```bash
leprecha@Ubuntu-DevOps:~$ chmod u+x learnlinux.spec
leprecha@Ubuntu-DevOps:~$ chmod 555 learnlinux.spec
leprecha@Ubuntu-DevOps:~$ ls -l learnlinux.spec
-r-xr-xr-x 1 leprecha sysadmin 0 Aug 20 19:09 learnlinux.spec
```

Common modes:

| Mode | Meaning |
| --- | --- |
| `644` | owner `rw-`, group `r--`, others `r--` |
| `600` | owner `rw-`, group `---`, others `---` |
| `755` | owner `rwx`, group `r-x`, others `r-x` |
| `740` | owner `rwx`, group `r--`, others `---` |

### Change owner/group

- `chown user file` - change owner
- `chgrp group file` - change group
- `chown user:group file` - change owner and group

Example:

```bash
leprecha@Ubuntu-DevOps:~$ sudo chown helpme learnlinux.spec
leprecha@Ubuntu-DevOps:~$ ls -l learnlinux.spec
-r-xr-xr-x 1 helpme sysadmin 0 Aug 20 19:09 learnlinux.spec
```

Recursive ownership change:

```bash
leprecha@Ubuntu-DevOps:~$ sudo chown -Rv helpme /path/to/dir
```

Use recursive mode carefully: always verify path first.

### Practice

1. Create `test_permissions.txt`.
2. Check initial permissions.
3. Set permissions to owner full, group read-only, others no access.
4. Check final permissions.
5. Change owner (if `helpme` user exists).

```bash
leprecha@Ubuntu-DevOps:~$ touch test_permissions.txt
leprecha@Ubuntu-DevOps:~$ ls -l test_permissions.txt
-rw-r--r-- 1 leprecha sysadmin 0 Aug 20 19:25 test_permissions.txt
leprecha@Ubuntu-DevOps:~$ chmod 740 test_permissions.txt
leprecha@Ubuntu-DevOps:~$ sudo chown helpme test_permissions.txt
leprecha@Ubuntu-DevOps:~$ ls -l test_permissions.txt
-rwxr----- 1 helpme sysadmin 0 Aug 20 19:25 test_permissions.txt
```

---

## 5. Lesson Summary

- **What I learned:** file navigation and inspection (`ls`, `cd`, `pwd`, `tree`, `stat`), editor basics (`nano`), file lifecycle (`cp`, `mv`, `rm`), and permission/ownership control (`chmod`, `chown`, `chgrp`).
- **What I practiced:** created files, copied to `/tmp`, moved and renamed files, removed files/directories, and applied numeric permissions (`740`, `555`).
- **Core concepts:** permission model (`u/g/o`, `r/w/x`), symbolic vs numeric `chmod`, and safe handling of recursive delete and ownership changes.
- **Needs repetition:** quick conversion between numeric and symbolic permissions; safe deletion flow (`preview -> confirm -> remove`).
- **Next step:** create a small script that prepares a practice folder and sets required permissions automatically.
