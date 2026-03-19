#!/usr/bin/env bash
# Description: Rename file extensions recursively with dry-run and verbose options.
# Usage: rename-ext.v2.sh [-n] [-v] <src_ext> <dst_ext> <dir>
# Notes: Uses find; -n for dry-run, -v for verbose output.
set -Eeuo pipefail
IFS=$'\n\t'

usage() {
  cat <<'USAGE'
Usage:
  rename-ext.v2.sh [-n] [-v] <src_ext> <dst_ext> <dir>

Examples:
  ./lessons/07-bash-scripting-automation/scripts/rename-ext.v2.sh txt md /tmp/lab7
  ./lessons/07-bash-scripting-automation/scripts/rename-ext.v2.sh -n txt md "/tmp/lab with spaces"
  ./lessons/07-bash-scripting-automation/scripts/rename-ext.v2.sh -v txt md /tmp/lab7
USAGE
}

dry=0
verbose=0

for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    usage
    exit 0
  fi
done

while getopts ":nvh" opt; do
  case "$opt" in
    n) dry=1 ;;
    v) verbose=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

shift $((OPTIND-1))
[[ $# -eq 3 ]] || { usage; exit 1; }

src=".$1"
dst=".$2"
dir="$3"
[[ -d "$dir" ]] || { echo "No dir: $dir" >&2; exit 1; }

export src dst dry verbose
find "$dir" -type f -name "*$src" -print0 |
  while IFS= read -r -d '' f; do
    new="${f%"$src"}$dst"
    (( verbose )) && printf '%s -> %s\n' "$f" "$new"
    (( dry )) || mv -- "$f" "$new"
  done
