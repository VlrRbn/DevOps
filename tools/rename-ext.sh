#!/usr/bin/env bash
set -Eeuo pipefail; IFS=$'\n\t'
usage(){ echo "Usage: $0 <src_ext> <dst_ext> <dir>"; }
[[ $# -eq 3 ]] || { usage; exit 1; }
src=".$1"; dst=".$2"; dir="$3"
[[ -d "$dir" ]] || { echo "No dir: $dir" >&2; exit 1; }
shopt -s nullglob
for f in "$dir"/*"$src"; do mv -- "$f" "${f%"$src"}$dst"; done
echo "Renamed in $dir: $src -> $dst"
