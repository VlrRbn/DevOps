#!/usr/bin/env bash
# Description: Create a shared directory with group ownership, SGID, and ACLs.
# Usage: mkshare.sh <group> <dir> [--sticky]
# Notes: Requires acl tools; optionally sets sticky bit.
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

