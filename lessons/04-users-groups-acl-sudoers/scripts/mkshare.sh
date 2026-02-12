#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  mkshare.sh <group> <dir> [--sticky]

Examples:
  mkshare.sh devs /srv/shared/dev
  mkshare.sh devs /srv/shared/dev --sticky
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

group="${1:-}"
dir="${2:-}"
opt="${3:-}"

if [[ -z "$group" || -z "$dir" ]]; then
  usage
  exit 1
fi

if [[ "$opt" != "" && "$opt" != "--sticky" ]]; then
  echo "Unsupported option: $opt" >&2
  usage
  exit 1
fi

if ! command -v setfacl >/dev/null 2>&1; then
  echo "setfacl is required. Install ACL package first." >&2
  echo "Ubuntu: sudo apt-get update && sudo apt-get install -y acl" >&2
  exit 1
fi

if ! getent group "$group" >/dev/null 2>&1; then
  sudo groupadd "$group"
fi

sudo mkdir -p "$dir"
sudo chown root:"$group" "$dir"
sudo chmod 2770 "$dir"

# Effective ACL for current directory
sudo setfacl -m g:"$group":rwx "$dir"
# Default ACL inherited by new files/directories
sudo setfacl -d -m g:"$group":rwx "$dir"

if [[ "$opt" == "--sticky" ]]; then
  sudo chmod +t "$dir"
fi

echo "OK: prepared $dir for group $group (SGID+ACL${opt:+ +sticky})"
