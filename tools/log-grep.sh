#!/usr/bin/env bash
# Description: Grep a pattern in a file or recursively in a directory.
# Usage: log-grep.sh <pattern> <file_or_dir> [grep-opts...]
# Notes: Uses grep -rEn for directories and grep -E for files.
set -Eeuo pipefail
[[ $# -ge 2 ]] || { echo "Usage: $0 <pattern> <file_or_dir> [grep-opts...]"; exit 1; }
pattern="$1"; target="$2"; shift 2
if [[ -d "$target" ]]; then
grep -rEn --color=always "$@" -e "$pattern" -- "$target"
else
grep -E --color=always "$@" -e "$pattern" -- "$target"
fi
