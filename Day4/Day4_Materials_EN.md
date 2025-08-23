# Day4_Materials_EN

# Users & Groups

---

**Date:** 23.08.2025

**Start time:** 14:00

**Total duration:** ~8h

---

## 🎯 Daily Goals

- Understand how Linux manages users and groups.
- Practice creating, modifying, and deleting users and groups.
- Connect users/groups management with file permissions.

---

## 📖 Theory

### Key Files

- `/etc/passwd` → user accounts.
- `/etc/group` → groups list.
- `/etc/shadow` → encrypted passwords (only root can view).

### User Commands

- `whoami` — show current user.
- `id` — show UID, GID, and groups.
- `groups` — list user’s groups.
- `adduser <name>` — create a new user.
- `userdel <name>` — delete a user.
- `usermod -aG <group> <user>` — add user to group.

### Group Commands

- `groupadd <name>` — create a group.
- `groupdel <name>` — delete a group.
- `gpasswd -a <user> <group>` — add user to group.
- `gpasswd -d <user> <group>` — remove user from group.

### Permissions & Ownership

- `chmod` — change permissions.
- `chown` — change file owner.
- `chgrp` — change group owner.

---

## 🛠 Practice

1. Check current user and groups:

```bash
whoami
id
groups
```

```bash
leprecha@Ubuntu-DevOps:~$ whoami
leprecha
leprecha@Ubuntu-DevOps:~$ id
uid=1000(leprecha) gid=1000(sysadmin) groups=1000(sysadmin),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),100(users),114(lpadmin)
leprecha@Ubuntu-DevOps:~$ groups
sysadmin adm cdrom sudo dip plugdev users lpadmin
```

1. Inspect system files:

```bash
cat /etc/passwd | tail -n 5
cat /etc/group | tail -n 5
sudo head -5 /etc/shadow
```

```bash
leprecha@Ubuntu-DevOps:~$ cat /etc/passwd | tail -n 5
nm-openvpn:x:121:122:NetworkManager OpenVPN,,,:/var/lib/openvpn/chroot:/usr/sbin/nologin
leprecha:x:1000:1000:Valerii:/home/leprecha:/bin/bash
helpme:x:1001:1001:Ivan Ivanov,1,12345,67890:/home/helpme:/bin/bash
nvidia-persistenced:x:122:124:NVIDIA Persistence Daemon,,,:/nonexistent:/usr/sbin/nologin
_flatpak:x:123:125:Flatpak system-wide installation helper,,,:/nonexistent:/usr/sbin/nologin
leprecha@Ubuntu-DevOps:~$ cat /etc/group | tail -n 5
gnome-initial-setup:x:985:
sysadmin:x:1000:
helpme:x:1001:
nvidia-persistenced:x:124:
_flatpak:x:125:
leprecha@Ubuntu-DevOps:~$ sudo head -5 /etc/shadow
[sudo] password for leprecha: 
root:*:20305:0:99999:7:::
daemon:*:20305:0:99999:7:::
bin:*:20305:0:99999:7:::
sys:*:20305:0:99999:7:::
sync:*:20305:0:99999:7:::
```

---

1. Create users `alice` and `bob`.

```bash
leprecha@Ubuntu-DevOps:~$ sudo adduser alice
leprecha@Ubuntu-DevOps:~$ sudo adduser bob
```

1. Create group `project`.
2. Add `alice` and `bob` to `project`.
3. Verify with `groups alice` / `id bob`.

```bash
leprecha@Ubuntu-DevOps:~$ sudo groupadd project
leprecha@Ubuntu-DevOps:~$ sudo usermod -aG project alice
leprecha@Ubuntu-DevOps:~$ groups alice
alice : alice users project
leprecha@Ubuntu-DevOps:~$ sudo usermod -aG project bob
leprecha@Ubuntu-DevOps:~$ groups bob
bob : bob users project
```

---

## 🔬 Mini-lab 1 — “Alice & Bob”

1. Create folder `/project_data`.
2. Assign it to group `project`:
    
    ```bash
    leprecha@Ubuntu-DevOps:~$ sudo mkdir -p /project_data
    leprecha@Ubuntu-DevOps:~$ sudo chgrp project /project_data
    leprecha@Ubuntu-DevOps:~$ sudo chmod 2770 /project_data
    leprecha@Ubuntu-DevOps:~$ sudo setfacl -m g:project:rwx /project_data
    leprecha@Ubuntu-DevOps:~$ sudo setfacl -d -m g:project:rwx /project_data
    #-d default
    ```
    

1. Test access with `alice` and `bob`.

```bash
leprecha@Ubuntu-DevOps:~$ sudo -u alice bash -lc 'echo "hello from alice" > /project_data/alice.txt && ls -l /project_data/alice.txt'
-rw-rw----+ 1 alice project 17 Aug 23 17:20 /project_data/alice.txt
leprecha@Ubuntu-DevOps:~$ sudo -u bob bash -lc 'cat /project_data/alice.txt && echo "and bob was here" >> /project_data/alice.txt && tail -n1 /project_data/alice.txt'
hello from alice
and bob was here
leprecha@Ubuntu-DevOps:~$ sudo -u bob bash -lc 'mkdir /project_data/bob_dir && echo "bob file" > /project_data/bob_dir/note.txt && ls -ld /project_data/bob_dir && ls -l /project_data/bob_dir'
drwxrws---+ 2 bob project 4096 Aug 23 17:25 /project_data/bob_dir
total 4
-rw-rw----+ 1 bob project 9 Aug 23 17:25 note.txt
```

---

## 🔬 Mini-lab 2 — “DevOps Team”

1. Create group `devops`.
2. Add multiple users (3–4 test users).

```bash
leprecha@Ubuntu-DevOps:~$ sudo  groupadd devops
leprecha@Ubuntu-DevOps:~$ for u in dev1 dev2 dev3; do sudo adduser --disabled-password --gecos "" "$u"; sudo usermod -aG devops "$u"; done
info: Adding user `dev1' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `dev1' (1006) ...
info: Adding new user `dev1' (1006) with group `dev1 (1006)' ...
info: Creating home directory `/home/dev1' ...
info: Copying files from `/etc/skel' ...
info: Adding new user `dev1' to supplemental / extra groups `users' ...
info: Adding user `dev1' to group `users' ...
info: Adding user `dev2' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `dev2' (1007) ...
info: Adding new user `dev2' (1007) with group `dev2 (1007)' ...
info: Creating home directory `/home/dev2' ...
info: Copying files from `/etc/skel' ...
info: Adding new user `dev2' to supplemental / extra groups `users' ...
info: Adding user `dev2' to group `users' ...
info: Adding user `dev3' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `dev3' (1008) ...
info: Adding new user `dev3' (1008) with group `dev3 (1008)' ...
info: Creating home directory `/home/dev3' ...
info: Copying files from `/etc/skel' ...
info: Adding new user `dev3' to supplemental / extra groups `users' ...
info: Adding user `dev3' to group `users' ...
```

1. Create a shared folder `/devops_share`.
2. Ensure only `devops` group members can access.

```bash
leprecha@Ubuntu-DevOps:~$ sudo mkdir -p /devops_share
leprecha@Ubuntu-DevOps:~$ sudo chgrp devops /devops_share
leprecha@Ubuntu-DevOps:~$ sudo chmod 2770 /devops_share
leprecha@Ubuntu-DevOps:~$ sudo setfacl -d -m g:devops:rwx /devops_share
leprecha@Ubuntu-DevOps:~$ sudo chmod +t /devops_share
leprecha@Ubuntu-DevOps:~$ sudo -u dev1 bash -lc 'echo "from dev1" > /devops_share/dev1.txt && ls -l /devops_share/dev1.txt'
-rw-rw----+ 1 dev1 devops 10 Aug 23 18:00 /devops_share/dev1.txt
leprecha@Ubuntu-DevOps:~$ sudo -u dev2 bash -lc 'cat /devops_share/dev1.txt && echo "dev2 was here" >> /devops_share/dev1.txt && tail -n1 /devops_share/dev1.txt'
from dev1
dev2 was here
leprecha@Ubuntu-DevOps:~$ sudo -u dev3 bash -lc 'mkdir /devops_share/dev3_dir && echo note > /devops_share/dev3_dir/note.txt && ls -ld /devops_share/dev3_dir && ls -l /devops_share/dev3_dir'
drwxrws---+ 2 dev3 devops 4096 Aug 23 18:12 /devops_share/dev3_dir
total 4
-rw-rw----+ 1 dev3 devops 5 Aug 23 18:12 note.txt
```

---

### 📖 Permissions & ACL under the microscope (umask, mask, sticky)

### 📌 **What is the umask**

**umask** (user file creation mask) — a "mask" that defines which permission bits will be removed from new files and directories by default.

In other words: **umask = filter**:

- A process tries to create a file with default maximum permissions.
- The kernel applies the umask → some rights are stripped away.

---

📝 **Base rules**

Maximum possible permissions:

- for a file: `666` (`rw-rw-rw-`) — no `x`, since a regular file shouldn’t be executable by default;
- for a directory: `777` (`rwxrwxrwx`).

**Final permissions = max_permissions - umask.**

---

🔎 **Examples**

- **umask = 022**
    - Removes `w` for group and others.
    - New files: `644` → `rw-r--r--`
    - New dirs: `755` → `rwxr-xr-x`
    - Default on most systems.
- **umask = 002**
    - Removes only `w` for others.
    - New files: `664` → `rw-rw-r--`
    - New dirs: `775` → `rwxrwxr-x`
    - Convenient for group collaboration.
- **umask = 077**
    - Removes all rights for group and others.
    - New files: `600` → `rw-------`
    - New dirs: `700` → `rwx------`
    - Full privacy, only the owner has access.

---

📌 **What is the ACL mask**

The **mask** in ACL is the *upper limit* of permissions for all **named users** and **named groups** (and also for `group::` if ACLs are enabled).

In other words:

- The file owner (`user::`) always has the rights defined in POSIX (Portable Operating System Interface).
- `others::` also has its rights directly defined.
- But all additional ACL entries (`group::`) go through the **mask**.

mask = the maximum that can be granted to those ACL entries.

---

📊 **Permission evaluation algorithm with ACL**

1. If current UID = owner → use `user::`.
2. Else, check `user:username`.
3. Else, check `group::` or `group:groupname` (if the process is in that group).
    
    ⚠️ Always apply the **mask** to these.
    
4. If nothing matches → fall back to `other::`.

**mask = real "permission filter"** for all groups and named users, it can downgrade  ACLs to “read-only” or even “nothing.”

---

## 🛠 Practice

1. Сreate test files in `/project_data` with different scenarios
2. Сheck effective permissions and ACL mask

```bash
# leprecha@Ubuntu-DevOps:~$ sudo setfacl -d -m g:project:rwx /project_data

leprecha@Ubuntu-DevOps:~$ sudo -u alice bash -lc 'umask 077; echo A > /project_data/u_077.txt'
leprecha@Ubuntu-DevOps:~$ sudo -u bob bash -lc 'umask 022; echo B > /project_data/u_022.txt'
leprecha@Ubuntu-DevOps:~$ sudo bash -lc 'ls -l /project_data/u_*.txt'

# the u_* is expanded **by your shell before sudo runs
# sudo bash -lc 'ls -l /project_data/u_*.txt'**

-rw-rw----+ 1 bob   project 2 Aug 23 19:11 /project_data/u_022.txt
-rw-rw----+ 1 alice project 2 Aug 23 19:10 /project_data/u_077.txt
leprecha@Ubuntu-DevOps:~$ sudo getfacl /project_data/u_077.txt
getfacl: Removing leading '/' from absolute path names
# file: project_data/u_077.txt
# owner: alice
# group: project
user::rw-
group::rwx			#effective:rw-
group:project:rwx		#effective:rw-
mask::rw-
other::---

# 600 - ACL
```

1. Cut the mask and then restore it

```bash
leprecha@Ubuntu-DevOps:~$ sudo setfacl -m m::rx /project_data
leprecha@Ubuntu-DevOps:~$ getfacl /project_data | sed -n '1,20p'
getfacl: Removing leading '/' from absolute path names
# file: project_data
# owner: root
# group: project
# flags: -s-
user::rwx
group::rwx	#effective:r-x
mask::r-x
other::---
default:user::rwx
default:group::rwx
default:group:project:rwx
default:mask::rwx
default:other::---

leprecha@Ubuntu-DevOps:~$ sudo setfacl -m m::rwx /project_data
leprecha@Ubuntu-DevOps:~$ getfacl /project_data | sed -n '1,20p'
getfacl: Removing leading '/' from absolute path names
# file: project_data
# owner: root
# group: project
# flags: -s-
user::rwx
group::rwx
mask::rwx
other::---
default:user::rwx
default:group::rwx
default:group:project:rwx
default:mask::rwx
default:other::---
```

1. Sticky bit (protection from deleting others’ files)

```bash
leprecha@Ubuntu-DevOps:~$ sudo -u bob bash -lc 'echo x > /project_data/tmp_by_bob && ls -l /project_data/tmp_by_bob'
-rw-rw----+ 1 bob project 2 Aug 23 19:32 /project_data/tmp_by_alice
leprecha@Ubuntu-DevOps:~$ sudo -u alice bash -lc 'rm /project_data/tmp_by_bob'
leprecha@Ubuntu-DevOps:~$ sudo chmod +t /project_data
leprecha@Ubuntu-DevOps:~$ ls -ld /project_data
drwxrws--T+ 3 root project 4096 Aug 23 19:32 /project_data
leprecha@Ubuntu-DevOps:~$ sudo -u alice bash -lc 'echo y > /project_data/tmp_by_bob'
leprecha@Ubuntu-DevOps:~$ sudo -u bob bash -lc 'rm /project_data/tmp_by_bob'
rm: cannot remove '/project_data/tmp_by_bob': Operation not permitted
```

---

### 📖 Account Policies (aging, lock/unlock, expire)

### 📝1. **Aging (password lifetime)**

File: `/etc/shadow`

Commands:

- View policy:
    
    ```bash
    leprecha@Ubuntu-DevOps:~$ sudo chage -l alice
    Last password change					: Aug 23, 2025
    Password expires					: never
    Password inactive					: never
    Account expires						: never
    Minimum number of days between password change		: 0
    Maximum number of days between password change		: 99999
    Number of days of warning before password expires	: 7
    ```
    
- Set password expiration — minimum 1 day, maximum 60, warn 7 days before:
    
    ```bash
    leprecha@Ubuntu-DevOps:~$ sudo chage -m 1 -M 60 -W 7 alice
    leprecha@Ubuntu-DevOps:~$ sudo chage -l alice
    Last password change					: Aug 23, 2025
    Password expires					: Oct 22, 2025
    Password inactive					: never
    Account expires						: never
    Minimum number of days between password change		: 1
    Maximum number of days between password change		: 60
    Number of days of warning before password expires	: 7
    ```
    

---

### 📝2. **Lock / Unlock (account lock)**

- Lock (adds `!` before the password hash in `/etc/shadow`):
    
    ```bash
    leprecha@Ubuntu-DevOps:~$ sudo usermod -L bob && sudo passwd -S bob
    bob L 2025-08-23 0 99999 7 -1
    ```
    
- Unlock:
    
    ```bash
    leprecha@Ubuntu-DevOps:~$ sudo usermod -U bob && sudo passwd -S bob
    bob P 2025-08-23 0 99999 7 -1
    ```
    
- Lock the shell (so login is impossible):
    
    ```bash
    leprecha@Ubuntu-DevOps:~$ sudo usermod -s /usr/sbin/nologin bob
    ```
    

---

### 📝3. **Expire (account expiration date)**

- Set a date after which the account will be disabled:
    
    ```bash
    leprecha@Ubuntu-DevOps:~$ sudo chage -E 2025-12-31 dev2
    leprecha@Ubuntu-DevOps:~$ sudo chage -l dev2
    Last password change					: Aug 23, 2025
    Password expires					: never
    Password inactive					: never
    Account expires						: Dec 31, 2025
    Minimum number of days between password change		: 0
    Maximum number of days between password change		: 99999
    Number of days of warning before password expires	: 7
    
    ```
    
- The lifetime of account **dev1** is +90 days:
    
    ```bash
    leprecha@Ubuntu-DevOps:~$ sudo chage -E "$(date -d '+90 days' +%Y-%m-%d)" dev1
    leprecha@Ubuntu-DevOps:~$ sudo chage -l dev1
    Last password change					: Aug 23, 2025
    Password expires					: never
    Password inactive					: never
    Account expires						: Nov 21, 2025
    Minimum number of days between password change		: 0
    Maximum number of days between password change		: 99999
    Number of days of warning before password expires	: 7
    ```
    
- This command searches `/etc/login.defs` for password policy settings:
    
    ```bash
    leprecha@Ubuntu-DevOps:~$ sudo grep -E 'PASS_(MIN|MAX|WARN)' /etc/login.defs
    #	PASS_MAX_DAYS	Maximum number of days a password may be used.
    #	PASS_MIN_DAYS	Minimum number of days allowed between password changes.
    #	PASS_WARN_AGE	Number of days warning given before a password expires.
    PASS_MAX_DAYS	99999
    PASS_MIN_DAYS	0
    PASS_WARN_AGE	7
    #PASS_MIN_LEN
    #PASS_MAX_LEN
    ```
    

---

### 📖 Sudoers with restrictions (least dangerous access)

## 🛠 Practice

Give a group the right to check service status and view unit logs, without full root.

1. Create the group and add a user:

```bash
leprecha@Ubuntu-DevOps:~$ sudo groupadd -f devopsadmin
leprecha@Ubuntu-DevOps:~$ sudo usermod -aG devopsadmin alice
leprecha@Ubuntu-DevOps:~$ groups alice
alice : alice users project devopsadmin
```

1. Allow everyone in the group to run without a password:
- only view the status of units;
- only view logs of specific units;
- File permissions and visudo check.

```bash
leprecha@Ubuntu-DevOps:~$ cat <<'EOF' | sudo tee /etc/sudoers.d/devopsadmin >/dev/null
Cmnd_Alias DEVOPS_SAFE = /usr/bin/systemctl status *, /usr/bin/journalctl -u *
%devopsadmin ALL=(root) NOPASSWD: DEVOPS_SAFE
EOF
leprecha@Ubuntu-DevOps:~$ sudo chmod 440 /etc/sudoers.d/devopsadmin
leprecha@Ubuntu-DevOps:~$ sudo visudo -cf /etc/sudoers.d/devopsadmin
/etc/sudoers.d/devopsadmin: parsed OK
leprecha@Ubuntu-DevOps:~$ sudo -l -U alice
Matching Defaults entries for alice on Ubuntu-DevOps:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin, use_pty

User alice may run the following commands on Ubuntu-DevOps:
    (root) NOPASSWD: /usr/bin/systemctl status *, /usr/bin/journalctl -u *
```

1. TEST:

```bash
leprecha@Ubuntu-DevOps:~$ su - alice
alice@Ubuntu-DevOps:~$ newgrp devopsadmin
# When you’re added to a new group (e.g. devopsadmin), the change doesn’t apply immediately
alice@Ubuntu-DevOps:~$ sudo -l
Matching Defaults entries for alice on Ubuntu-DevOps:
    env_reset, mail_badpass,
    secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin,
    use_pty

User alice may run the following commands on Ubuntu-DevOps:
    (root) NOPASSWD: /usr/bin/systemctl status *, /usr/bin/journalctl -u *
alice@Ubuntu-DevOps:~$ sudo systemctl status cron |head -n3
● cron.service - Regular background program processing daemon
     Loaded: loaded (/usr/lib/systemd/system/cron.service; enabled; preset: enabled)
     Active: active (running) since Sat 2025-08-23 16:09:35 IST; 4h 12min ago
alice@Ubuntu-DevOps:~$ sudo journalctl -u cron --since "5 min ago" | tail -n5
-- No entries --
alice@Ubuntu-DevOps:~$ exit
exit
```

📌 Summary:

- `chage` manages **password/account lifetime policies**.
- `usermod -L / -U` manages **locking/unlocking accounts**.
- `nologin` turns a user into a **service account** (no login).

---

## Done

- Created users: `alice`, `bob`, `dev1–dev3`.
- Groups: `project`, `devops`.
- Shared directories with inherited permissions:
    - `/project_data` → `project` + SGID + default ACL.
    - `/devops_share` → `devops` + SGID + default ACL.
- Verified access: read/write between group members works.

**Key commands**

```bash
adduser / userdel / usermod -aG
groupadd / groupdel / gpasswd -a|-d
ls -l / getent passwd|group
chmod 2770 / chgrp / chown
setfacl -m ... / setfacl -d -m ...
getfacl
```

**Details**

- SGID on a directory ⇒ all new files inherit the **group**.
- Default ACL (`setfacl -d`) ⇒ group always has the required RWX.
- For "protection against deleting other users’ files," you can add the sticky bit:

```bash
sudo chmod +t /devops_share
```

---

## 📝 Daily Summary

- Understood `/etc/passwd`, `/etc/group`, `/etc/shadow` (fields & password aging).
- Created users & groups; managed group membership.
- Built shared directories with SGID + default ACLs for team collaboration.
- Verified cross-user read/write using `sudo -u`.
- **To revisit:** `chmod` (symbolic/octal), `setfacl/getfacl`, `chage -l, sudo -l, visudo -c.`
- Artifacts: labs/day4/SGID_ACL_v1.md, tools/mkshare.sh.