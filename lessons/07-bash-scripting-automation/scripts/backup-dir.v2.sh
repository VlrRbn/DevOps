#!/usr/bin/env bash
# Description: Backup a directory to ~/backups with optional exclude pattern and retention.
# Usage: backup-dir.v2.sh <dir> [--keep N] [--exclude PATTERN]
# --exclude uses tar glob patterns (not regex). Quote patterns with * ? [] to avoid shell expansion.
# Examples:
#   --exclude 'node_modules'        # exclude any path containing node_modules
#   --exclude '*/node_modules/*'    # exclude node_modules contents anywhere (more explicit)
#   --exclude '*.log'               # exclude log files
#   --exclude '*/.git/*'            # exclude .git contents anywhere
# Notes: Uses a lock to avoid concurrent runs, validates the archive, and logs to syslog.
set -Eeuo pipefail
IFS=$'\n\t'

keep=5
exclude=''
dir=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)
      keep="${2:-5}"
      shift 2
      ;;
    --exclude)
      exclude="${2:-}"
      shift 2
      ;;
    *)
      dir="${1}"
      shift
      ;;
  esac
done

[[ -n "$dir" && -d "$dir" ]] || { echo "Usage: $0 <dir> [--keep N] [--exclude PATTERN]"; exit 1; }

out="$HOME/backups"
mkdir -p -- "$out"

ts=$(date +%Y%m%d_%H%M%S)
base=$(basename -- "$dir")
tarball="$out/${base}_${ts}.tar.gz"
lock="/tmp/backup-$base.lock"

cmd=(tar -C "$(dirname -- "$dir")" -czf "$tarball")
[[ -n "$exclude" ]] && cmd+=("--exclude=$exclude")
cmd+=("$base")

{
  flock -n 9 || { echo "Another backup is in progress for $base" >&2; exit 1; }
  "${cmd[@]}"
  tar -tzf "$tarball" >/dev/null
} 9> "$lock"

logger -t backup "Created $tarball"
find "$out" -maxdepth 1 -type f -name "${base}_*.tar.gz" -printf "%T@ %p\n" |
  sort -rn |
  tail -n +$((keep + 1)) |
  cut -d' ' -f2- |
  xargs -r rm -f

echo "OK: $tarball (keep last $keep)"
