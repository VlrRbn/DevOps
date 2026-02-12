# lesson_04

# Users, Groups, ACL, Umask, and Sudoers

**Date:** 2025-08-23  
**Topic:** Local account management, group collaboration model, access control, and least-privilege sudo rules  
**Daily goal:** Build a practical model for multi-user collaboration with safe permissions and controlled admin access.
**Bridge:** [00 Foundations Bridge](../00-foundations-bridge/00-foundations-bridge.md) for missing basics after lessons 1-4.

---

## 1. Core Concepts

### 1.1 Identity model in Linux

Linux access decisions are based on:

- **User ID (UID)**
- **Primary Group ID (GID)**
- **Supplementary groups**
- **Permission bits and ACL entries**

Useful files:

- `/etc/passwd` - users (account metadata, shell, home)
- `/etc/group` - groups and membership
- `/etc/shadow` - password hashes and aging policy (root-readable)

### 1.2 Ownership and permissions

Each file/dir has:

- owner (user)
- group
- permissions for `user/group/others`

Extra mechanics used in team directories:

- **SGID bit on directory** (`chmod 2xxx`) - new files inherit directory group
- **Default ACL** (`setfacl -d`) - inherited ACL policy for newly created entries
- **Sticky bit** (`chmod +t`) - only owner/root can delete entries in that directory
- **umask** - default permission filter at file creation time
- **ACL mask** - upper bound for effective ACL rights of groups/named users

---

## 2. Command Priority (What to Learn First)

### Core (must know now)

- `whoami`, `id`, `groups`
- `getent passwd`, `getent group`
- `adduser`, `userdel` (or `deluser`)
- `groupadd`, `groupdel`
- `usermod -aG`
- `chown`, `chgrp`, `chmod`

### Optional (useful after core)

- `gpasswd -a`, `gpasswd -d`
- `chage -l`, `chage -m/-M/-W/-E`
- `usermod -L`, `usermod -U`, `usermod -s /usr/sbin/nologin`
- `newgrp`

### Advanced (deeper admin work)

- `setfacl`, `getfacl`
- ACL mask tuning (`setfacl -m m::...`)
- `visudo -cf`
- scoped sudo rules in `/etc/sudoers.d/*`

---

## 3. Core Commands: What / Why / When

### `whoami`, `id`, `groups`

- **What:** current identity and group context
- **Why:** first sanity check for permission issues
- **When:** before troubleshooting access problems

```bash
whoami
id
groups
```

### `getent passwd`, `getent group`

- **What:** account/group entries from NSS sources
- **Why:** safer than only reading local files directly
- **When:** verify that user/group really exists

```bash
getent passwd alice
getent group project
```

### `adduser` and `userdel`

- **What:** create/remove user account
- **Why:** day-to-day account lifecycle
- **When:** onboarding/offboarding users

```bash
sudo adduser alice
sudo adduser bob
sudo userdel -r bob   # -r removes home and mail spool
```

### `groupadd`, `usermod -aG`

- **What:** create group and add supplementary membership
- **Why:** grant shared access through group model
- **When:** building team/project access

```bash
sudo groupadd project
sudo usermod -aG project alice
sudo usermod -aG project bob
id alice
id bob
```

### `chgrp`, `chmod`, `chown`

- **What:** set group ownership, permissions, and owner
- **Why:** define directory access rules
- **When:** preparing shared workspaces

```bash
sudo chgrp project /project_data
sudo chmod 2770 /project_data
sudo chown root:project /project_data
```

---

## 4. Mini-lab 1: Alice and Bob Collaboration

### 4.1 Goal

Create a shared directory where project members can read/write each other files and new files inherit project group.

### 4.2 Setup

```bash
sudo adduser alice
sudo adduser bob
sudo groupadd -f project
sudo usermod -aG project alice
sudo usermod -aG project bob

sudo mkdir -p /project_data
sudo chown root:project /project_data
sudo chmod 2770 /project_data
sudo setfacl -d -m g:project:rwx /project_data
```

Meaning:

- `2770` = `rwxrws---` (SGID enabled)
- default ACL keeps group access inherited

### 4.3 Test with both users

```bash
sudo -u alice bash -lc 'echo "hello from alice" > /project_data/alice.txt && ls -l /project_data/alice.txt'
sudo -u bob bash -lc 'cat /project_data/alice.txt && echo "and bob was here" >> /project_data/alice.txt && tail -n1 /project_data/alice.txt'
sudo -u bob bash -lc 'mkdir /project_data/bob_dir && echo "bob file" > /project_data/bob_dir/note.txt && ls -ld /project_data/bob_dir && ls -l /project_data/bob_dir'
```

Expected:

- created entries keep group `project`
- both users can modify shared files

---

## 5. Permission Mechanics Under the Microscope

### 5.1 umask

**umask** removes permission bits from default creation modes.

Base modes:

- file base: `666`
- directory base: `777`

Examples:

- `umask 022` -> files `644`, dirs `755`
- `umask 002` -> files `664`, dirs `775`
- `umask 077` -> files `600`, dirs `700`

### 5.2 ACL mask

ACL `mask::` is an upper limit for:

- `group::`
- named user entries (`user:...`)
- named group entries (`group:...`)

So entry may look permissive (`rwx`) but effective rights can be lower due to mask.

### 5.3 Practical check

```bash
sudo -u alice bash -lc 'umask 077; echo A > /project_data/u_077.txt'
sudo -u bob bash -lc 'umask 022; echo B > /project_data/u_022.txt'
sudo bash -lc 'ls -l /project_data/u_*.txt'
sudo getfacl /project_data/u_077.txt
```

### 5.4 Tuning ACL mask

```bash
sudo setfacl -m m::rx /project_data
sudo getfacl /project_data | sed -n '1,20p'

# restore broader mask for collaboration
sudo setfacl -m m::rwx /project_data
```

### 5.5 Sticky bit behavior

Sticky bit protects against deleting another user's file in shared dirs.

```bash
sudo chmod +t /project_data
ls -ld /project_data
```

Without sticky bit, users with write on directory can delete each other files.
With sticky bit, only file owner/root can delete file.

---

## 6. Mini-lab 2: DevOps Team Share

### 6.1 Goal

Set up a team share for multiple users with inherited group ownership and safe deletion behavior.

### 6.2 Setup

```bash
sudo groupadd -f devops
for u in dev1 dev2 dev3; do
  sudo adduser --disabled-password --gecos "" "$u"
  sudo usermod -aG devops "$u"
done

sudo mkdir -p /devops_share
sudo chown root:devops /devops_share
sudo chmod 2770 /devops_share
sudo setfacl -d -m g:devops:rwx /devops_share
sudo chmod +t /devops_share
```

### 6.3 Verify behavior

```bash
sudo -u dev1 bash -lc 'echo "from dev1" > /devops_share/dev1.txt && ls -l /devops_share/dev1.txt'
sudo -u dev2 bash -lc 'cat /devops_share/dev1.txt && echo "dev2 was here" >> /devops_share/dev1.txt && tail -n1 /devops_share/dev1.txt'
sudo -u dev3 bash -lc 'mkdir /devops_share/dev3_dir && echo note > /devops_share/dev3_dir/note.txt && ls -ld /devops_share/dev3_dir && ls -l /devops_share/dev3_dir'
```

---

## 7. Account Policy Controls

### 7.1 Password aging (`chage`)

```bash
sudo chage -l alice
sudo chage -m 1 -M 60 -W 7 alice
sudo chage -l alice
```

### 7.2 Lock and unlock account

```bash
sudo usermod -L bob && sudo passwd -S bob
sudo usermod -U bob && sudo passwd -S bob
```

### 7.3 Disable interactive login shell

```bash
sudo usermod -s /usr/sbin/nologin bob
```

### 7.4 Account expiration date

```bash
sudo chage -E 2025-12-31 dev2
sudo chage -E "$(date -d '+90 days' +%Y-%m-%d)" dev1
sudo chage -l dev2
sudo chage -l dev1
```

---

## 8. Restricted Sudoers (Least Privilege)

### 8.1 Goal

Allow a support group to inspect service status and logs without full root shell.

### 8.2 Setup group and membership

```bash
sudo groupadd -f devopsadmin
sudo usermod -aG devopsadmin alice
groups alice
```

### 8.3 Create scoped sudo policy

```bash
cat <<'EOF' | sudo tee /etc/sudoers.d/devopsadmin >/dev/null
Cmnd_Alias DEVOPS_SAFE = /usr/bin/systemctl status *, /usr/bin/journalctl -u *
%devopsadmin ALL=(root) NOPASSWD: DEVOPS_SAFE
EOF

sudo chmod 440 /etc/sudoers.d/devopsadmin
sudo visudo -cf /etc/sudoers.d/devopsadmin
sudo -l -U alice
```

### 8.4 Test as target user

```bash
su - alice
newgrp devopsadmin
sudo -l
sudo systemctl status cron | head -n3
sudo journalctl -u cron --since "5 min ago" | tail -n5
exit
```

---

## 9. Automation: Shared Directory Bootstrap Script

Script path:

- `lessons/04-users-groups-acl-sudoers/scripts/mkshare.sh`

What it automates:

1. Ensure target group exists.
2. Create target directory.
3. Apply `root:<group>` ownership.
4. Apply SGID permissions (`2770`).
5. Apply ACL for group rwx (effective + default).
6. Optionally apply sticky bit.

Run example:

```bash
chmod +x lessons/04-users-groups-acl-sudoers/scripts/mkshare.sh
lessons/04-users-groups-acl-sudoers/scripts/mkshare.sh devs /srv/shared/dev --sticky
ls -ld /srv/shared/dev
getfacl /srv/shared/dev | sed -n '1,20p'
```

---

## 10. Cleanup (Optional)

If this is a throwaway lab machine, you can clean entities created in this lesson.

```bash
sudo userdel -r alice 2>/dev/null || true
sudo userdel -r bob 2>/dev/null || true
for u in dev1 dev2 dev3; do sudo userdel -r "$u" 2>/dev/null || true; done

sudo groupdel project 2>/dev/null || true
sudo groupdel devops 2>/dev/null || true
sudo groupdel devopsadmin 2>/dev/null || true

sudo rm -rf /project_data /devops_share
sudo rm -f /etc/sudoers.d/devopsadmin
```

---

## 11. Lesson Summary

- **What I learned:** how Linux ties user identity, groups, and access control together.
- **What I practiced:** creating users/groups, setting shared directories, and validating cross-user access.
- **Core concepts:** SGID inheritance, default ACL, ACL mask, sticky bit, and account policy controls.
- **Security focus:** least-privilege sudoers with command-level scope instead of broad root access.
- **Next step:** build reusable admin scripts and apply same model to service-specific directories.
