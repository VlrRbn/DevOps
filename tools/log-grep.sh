#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -ge 2 ]] || { echo "Usage: $0 <pattern> <file_or_dir> [grep-opts...]"; exit 1; }
pattern="$1"; target="$2"; shift 2
if [[ -d "$target" ]]; then
grep -rEn --color=always "$@" -e "$pattern" -- "$target"
else
grep -E --color=always "$@" -e "$pattern" -- "$target"
fi
