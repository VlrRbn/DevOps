# Shared Directory Script (Lesson 04)

`mkshare.sh` prepares a shared directory for a Unix group using:

- group ownership (`root:<group>`)
- SGID on directory (`2770`)
- ACL for group access (`setfacl`)
- optional sticky bit (`--sticky`)

## Files

- `mkshare.sh`

## Requirements

- `bash`
- `sudo`
- `getent` (from libc tools on most systems)
- `setfacl` / `getfacl` (ACL package)

Install ACL on Ubuntu if needed:

```bash
sudo apt-get update
sudo apt-get install -y acl
```

## Usage

From repo root:

```bash
lessons/04-users-groups-acl-sudoers/scripts/mkshare.sh <group> <dir> [--sticky]
```

Examples:

```bash
lessons/04-users-groups-acl-sudoers/scripts/mkshare.sh devs /srv/shared/dev
lessons/04-users-groups-acl-sudoers/scripts/mkshare.sh devs /srv/shared/dev --sticky
```

## What It Does

1. Checks that `<group>` exists; creates it if missing.
2. Creates `<dir>` if missing.
3. Sets owner/group to `root:<group>`.
4. Applies `chmod 2770` (SGID + group RWX).
5. Sets effective ACL `g:<group>:rwx`.
6. Sets default ACL `d:g:<group>:rwx` for inheritance.
7. Adds sticky bit if `--sticky` is passed.

## Verification

```bash
ls -ld /srv/shared/dev
getfacl /srv/shared/dev | sed -n '1,30p'
```

You should see:

- group = target group
- SGID bit (`s`) on directory permissions
- ACL entries for target group
- default ACL entries for inheritance

## Exit Behavior

- exits with non-zero code on validation/setup errors
- prints success message on completion

## Safety Notes

- The script uses `sudo` for system-level changes.
- Run it only for directories you intend to share.
- Prefer testing first in `/tmp` or lab paths.
