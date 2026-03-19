#!/usr/bin/env bash
# Description: Create a timestamped tar.gz backup of a directory and keep the last N copies.
# Usage: backup-dir.sh <dir> [--keep N]
# Output: Tarballs in ~/backups named <dir>_YYYYMMDD_HHMM.tar.gz.
set -Eeuo pipefail
IFS=$'\n\t'

usage() {
  cat <<'USAGE'
Usage:
  backup-dir.sh <dir> [--keep N]

Examples:
  ./lessons/07-bash-scripting-automation/scripts/backup-dir.sh /tmp/lab7
  ./lessons/07-bash-scripting-automation/scripts/backup-dir.sh /tmp/lab7 --keep 3
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

keep=5
[[ $# -ge 1 ]] || { usage; exit 1; }

dir="$1"
shift || true
[[ "${1:-}" == "--keep" ]] && keep="${2:-5}"
[[ -d "$dir" ]] || { echo "No dir: $dir" >&2; exit 1; }

out=~/backups
mkdir -p "$out"

ts=$(date +%Y%m%d_%H%M)
base=$(basename "$dir")
tarball="$out/${base}_${ts}.tar.gz"

tar -C "$(dirname "$dir")" -czf "$tarball" "$base"
ls -1t -- "$out"/"${base}"_* 2>/dev/null |
  tail -n +$((keep + 1)) |
  tr '\n' '\0' |
  xargs -0 -r rm -f

echo "Created: $tarball (kept last $keep)"
