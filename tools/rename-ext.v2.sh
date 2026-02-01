#!/usr/bin/env bash
# Description: Rename file extensions recursively with dry-run and verbose options.
# Usage: rename-ext.v2.sh [-n] [-v] <src_ext> <dst_ext> <dir>
# Notes: Uses find; -n for dry-run, -v for verbose output.
set -Eeuo pipefail
IFS=$'\n\t'
usage(){ echo "Usage: $0 [-n] [-v] <src_ext> <dst_ext> <dir>"; }
dry=0
verbose=0
while getopts ":nv" opt; do case "$opt" in n) dry=1;; v) verbose=1;; *) usage; exit 1;; esac; done
shift $((OPTIND-1))
[[ $# -eq 3 ]] || { usage; exit 1; }
src=".$1"
dst=".$2"
dir="$3"
[[ -d "$dir" ]] || { echo "No dir: $dir" >&2; exit 1; }
export src dst dry verbose
find "$dir" -type f -name "*$src" -print0 | while IFS= read -r -d '' f; do
new="${f%"$src"}$dst"
(( verbose )) && printf '%s -> %s\n' "$f" "$new"
(( dry )) || mv -- "$f" "$new"
done
