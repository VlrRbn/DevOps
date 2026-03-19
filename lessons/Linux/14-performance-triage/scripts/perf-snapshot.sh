#!/usr/bin/env bash
# Description: Save a performance snapshot directory and package it as tar.gz.
# Usage: perf-snapshot.sh [--out-dir DIR] [--seconds N]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  perf-snapshot.sh [--out-dir DIR] [--seconds N]

Defaults:
  --out-dir /tmp
  --seconds 5

Examples:
  ./lessons/14-performance-triage/scripts/perf-snapshot.sh
  ./lessons/14-performance-triage/scripts/perf-snapshot.sh --out-dir /tmp/lesson14-artifacts --seconds 8
USAGE
}

OUT_DIR="/tmp"
SECONDS_N="5"

# Parse CLI options.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --out-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --out-dir requires value" >&2; exit 2; }
      OUT_DIR="$2"
      shift 2
      ;;
    --seconds)
      [[ $# -ge 2 ]] || { echo "ERROR: --seconds requires value" >&2; exit 2; }
      SECONDS_N="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[[ "$SECONDS_N" =~ ^[0-9]+$ ]] || { echo "ERROR: --seconds must be integer" >&2; exit 2; }
(( SECONDS_N >= 1 )) || { echo "ERROR: --seconds must be >= 1" >&2; exit 2; }

# Validate baseline tooling.
for cmd in mkdir cp date hostname uname uptime free ps vmstat lsblk findmnt journalctl tar basename; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

STAMP="$(date +%Y%m%d_%H%M%S)"
SNAP_DIR="$OUT_DIR/perf-snapshot_${STAMP}"
ARCHIVE_PATH="${SNAP_DIR}.tar.gz"
mkdir -p "$SNAP_DIR"

# Capture host metadata for correlation with external monitoring.
{
  echo "timestamp=$(date '+%F %T')"
  echo "host=$(hostname)"
  echo "kernel=$(uname -a)"
  echo "uptime=$(uptime -p 2>/dev/null || true)"
  echo "seconds_sample=$SECONDS_N"
} > "$SNAP_DIR/meta.txt"

# Core system snapshots.
uptime > "$SNAP_DIR/uptime.txt" 2>&1 || true
cat /proc/loadavg > "$SNAP_DIR/loadavg.txt" 2>&1 || true
free -h > "$SNAP_DIR/free-h.txt" 2>&1 || true
cp -a /proc/meminfo "$SNAP_DIR/meminfo.txt" 2>/dev/null || true
lsblk -f > "$SNAP_DIR/lsblk-f.txt" 2>&1 || true
findmnt -A > "$SNAP_DIR/findmnt-A.txt" 2>&1 || true

# Process-level top views.
ps -eo pid,ppid,user,comm,%cpu,%mem,state --sort=-%cpu | head -n 80 > "$SNAP_DIR/ps-top-cpu.txt" 2>&1 || true
ps -eo pid,ppid,user,comm,%cpu,%mem,state --sort=-%mem | head -n 80 > "$SNAP_DIR/ps-top-mem.txt" 2>&1 || true

# Time-sampled VM stats.
vmstat 1 "$SECONDS_N" > "$SNAP_DIR/vmstat.txt" 2>&1 || true

# Optional deeper metrics when sysstat is installed.
if command -v iostat >/dev/null 2>&1; then
  iostat -xz 1 "$SECONDS_N" > "$SNAP_DIR/iostat-xz.txt" 2>&1 || true
fi
if command -v pidstat >/dev/null 2>&1; then
  pidstat 1 "$SECONDS_N" > "$SNAP_DIR/pidstat.txt" 2>&1 || true
fi
if command -v mpstat >/dev/null 2>&1; then
  mpstat -P ALL 1 "$SECONDS_N" > "$SNAP_DIR/mpstat-all.txt" 2>&1 || true
fi

# Include batch top output when available.
if command -v top >/dev/null 2>&1; then
  top -b -n 1 > "$SNAP_DIR/top-batch.txt" 2>&1 || true
fi

# Log context for recent performance-related warnings/errors.
journalctl --since "-30 min" -p warning..alert --no-pager > "$SNAP_DIR/journal-warning-alert-30m.txt" 2>&1 || true

# Kernel context. Keep dmesg optional: missing/unprivileged dmesg must not break the whole snapshot.
# We still write dmesg-err-warn.txt with an INFO message so artifact set stays predictable.
# Avoid sudo probing here to keep snapshot non-interactive and log-clean.
if command -v dmesg >/dev/null 2>&1; then
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    dmesg --level=err,warn > "$SNAP_DIR/dmesg-err-warn.txt" 2>&1 || {
      echo "[INFO] dmesg capture failed even as root" > "$SNAP_DIR/dmesg-err-warn.txt"
    }
  else
    {
      echo "[INFO] skipped dmesg capture: insufficient privileges"
      echo "[INFO] run perf-snapshot with sudo to include kernel warnings/errors"
    } > "$SNAP_DIR/dmesg-err-warn.txt"
  fi
else
  {
    echo "[INFO] skipped dmesg capture: dmesg command not found"
    echo "[INFO] install util-linux/procps package set to enable kernel log capture"
  } > "$SNAP_DIR/dmesg-err-warn.txt"
fi

# Package snapshot to single archive for sharing/attachment.
tar -C "$OUT_DIR" -czf "$ARCHIVE_PATH" "$(basename "$SNAP_DIR")"

echo "[OK] performance snapshot created"
echo "[INFO] path: $SNAP_DIR"
echo "[INFO] archive: $ARCHIVE_PATH"
