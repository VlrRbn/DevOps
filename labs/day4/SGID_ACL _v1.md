# SGID_ACL

## **Automation**: minimal share creator

**Purpose:**

Create a shared directory for a Unix group with proper permissions (SGID + ACL).

**Usage:**

```bash
chmod +x mkshare.sh
./mkshare.sh devs /srv/shared/dev --sticky
ls -ld /srv/shared/dev
getfacl /srv/shared/dev | sed -n '1,20p'
```

**Parameters:**

- `<group>` – target Unix group (created if it doesn’t exist).
- `<dir>` – directory path to be created/shared.

**What it does:**

1. Ensures the group exists ( `getent … || groupadd` )
2. Creates the directory if missing.
3. Sets group ownership to `<group>`.
4. Applies SGID bit (so new files inherit the group).
5. Grants group **rwx** access via ACL (default + effective).
6. Ensures default ACL so new files/dirs inherit group rwx.
    
    Note: requires acl package.
    
    ```bash
    command -v setfacl >/dev/null || { sudo apt-get update && sudo apt-get install -y acl; }
    ```
    

```bash
#!/usr/bin/env bash
# requires: acl (setfacl/getfacl). Ubuntu: sudo apt-get install -y acl
group="$1"
dir="$2"
opt="${3:-}"

if [ -z "$group" ] || [ -z "$dir" ]; then
  echo "Usage: $0 <group> <dir> [--sticky]"
  exit 1
fi

if ! getent group "$group" >/dev/null; then
  sudo groupadd "$group"
fi

sudo mkdir -p "$dir"
sudo chgrp "$group" "$dir"
sudo chmod 2770 "$dir"

sudo setfacl -m g:"$group":rwx "$dir"
sudo setfacl -d -m g:"$group":rwx "$dir"

[ "$opt" = "--sticky" ] && sudo chmod +t "$dir"

echo "OK: $dir owned by :$group (SGID+ACL${opt:+ +sticky})"

```