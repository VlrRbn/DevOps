#!/usr/bin/env bash
# Description: Rename file extensions in a directory (non-recursive).
# Usage: rename-ext.sh <src_ext> <dst_ext> <dir>
# Notes: Only files directly under <dir> are renamed.
set -Eeuo pipefail
IFS=$'\n\t'

usage() {
  cat <<'USAGE'
Usage:
  rename-ext.sh <src_ext> <dst_ext> <dir>

Examples:
  ./lessons/07-bash-scripting-automation/scripts/rename-ext.sh txt md /tmp/lab7
  ./lessons/07-bash-scripting-automation/scripts/rename-ext.sh log txt /var/tmp/demo
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ $# -eq 3 ]] || { usage; exit 1; }
src=".$1"
dst=".$2"
dir="$3"
[[ -d "$dir" ]] || { echo "No dir: $dir" >&2; exit 1; }

shopt -s nullglob

for f in "$dir"/*"$src"; do
  mv -- "$f" "${f%"$src"}$dst"
done

echo "Renamed in $dir: $src -> $dst"
