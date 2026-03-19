#!/usr/bin/env bash
# Description: Capture final Linux capstone evidence bundle and archive it.
# Usage: capstone-snapshot.sh [--out-dir DIR] [--since STR] [--seconds N]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  capstone-snapshot.sh [--out-dir DIR] [--since STR] [--seconds N]

Defaults:
  --out-dir /tmp
  --since "-2h"
  --seconds 5

Examples:
  ./lessons/15-linux-capstone-incident-runbook/scripts/capstone-snapshot.sh
  ./lessons/15-linux-capstone-incident-runbook/scripts/capstone-snapshot.sh --out-dir /tmp/lesson15-artifacts --since "-4h" --seconds 8
USAGE
}

OUT_DIR="/tmp"
SINCE="-2h"
SECONDS_N="5"

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
    --since)
      [[ $# -ge 2 ]] || { echo "ERROR: --since requires value" >&2; exit 2; }
      SINCE="$2"
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

for cmd in mkdir cp date hostname uname uptime free ps vmstat lsblk findmnt ip ss journalctl tar basename; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

STAMP="$(date +%Y%m%d_%H%M%S)"
SNAP_DIR="$OUT_DIR/capstone-snapshot_${STAMP}"
ARCHIVE_PATH="${SNAP_DIR}.tar.gz"
mkdir -p "$SNAP_DIR"

{
  echo "timestamp=$(date '+%F %T')"
  echo "host=$(hostname)"
  echo "kernel=$(uname -a)"
  echo "journal_since=$SINCE"
  echo "seconds_sample=$SECONDS_N"
} > "$SNAP_DIR/meta.txt"

# Save config files that frequently matter in Linux incidents.
for file in /etc/fstab /etc/hosts /etc/resolv.conf /etc/nftables.conf /etc/sysctl.conf /etc/ssh/sshd_config; do
  if [[ -f "$file" ]]; then
    cp -a "$file" "$SNAP_DIR/"
  fi
done

if [[ -d /etc/systemd/system ]]; then
  mkdir -p "$SNAP_DIR/systemd"
  cp -a /etc/systemd/system/*.service "$SNAP_DIR/systemd/" 2>/dev/null || true
  cp -a /etc/systemd/system/*.mount "$SNAP_DIR/systemd/" 2>/dev/null || true
  cp -a /etc/systemd/system/*.timer "$SNAP_DIR/systemd/" 2>/dev/null || true
fi

# Baseline runtime snapshots.
uptime > "$SNAP_DIR/uptime.txt" 2>&1 || true
cat /proc/loadavg > "$SNAP_DIR/loadavg.txt" 2>&1 || true
free -h > "$SNAP_DIR/free-h.txt" 2>&1 || true
df -h > "$SNAP_DIR/df-h.txt" 2>&1 || true
lsblk -f > "$SNAP_DIR/lsblk-f.txt" 2>&1 || true
findmnt -A > "$SNAP_DIR/findmnt-A.txt" 2>&1 || true
findmnt --verify > "$SNAP_DIR/findmnt-verify.txt" 2>&1 || true

# Process and scheduler snapshots.
ps -eo pid,ppid,user,comm,%cpu,%mem,state --sort=-%cpu | head -n 80 > "$SNAP_DIR/ps-top-cpu.txt" 2>&1 || true
ps -eo pid,ppid,user,comm,%cpu,%mem,state --sort=-%mem | head -n 80 > "$SNAP_DIR/ps-top-mem.txt" 2>&1 || true
vmstat 1 "$SECONDS_N" > "$SNAP_DIR/vmstat.txt" 2>&1 || true
if command -v top >/dev/null 2>&1; then
  top -b -n 1 > "$SNAP_DIR/top-batch.txt" 2>&1 || true
fi

# Network snapshots.
ip -brief addr > "$SNAP_DIR/ip-brief-addr.txt" 2>&1 || true
ip route > "$SNAP_DIR/ip-route.txt" 2>&1 || true
ss -tulpen > "$SNAP_DIR/ss-tulpen.txt" 2>&1 || true

# systemd/journal context.
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-system-running > "$SNAP_DIR/system-state.txt" 2>&1 || true
  systemctl list-units --failed --no-pager --plain > "$SNAP_DIR/failed-units.txt" 2>&1 || true
fi
journalctl --since "$SINCE" -p warning..alert --no-pager > "$SNAP_DIR/journal-warning-alert.txt" 2>&1 || true

# dmesg is optional; keep output file predictable even without command/privileges.
if command -v dmesg >/dev/null 2>&1; then
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    dmesg --level=err,warn > "$SNAP_DIR/dmesg-err-warn.txt" 2>&1 || {
      echo "[INFO] dmesg capture failed even as root" > "$SNAP_DIR/dmesg-err-warn.txt"
    }
  else
    {
      echo "[INFO] skipped dmesg capture: insufficient privileges"
      echo "[INFO] run capstone-snapshot with sudo to include kernel warnings/errors"
    } > "$SNAP_DIR/dmesg-err-warn.txt"
  fi
else
  {
    echo "[INFO] skipped dmesg capture: dmesg command not found"
  } > "$SNAP_DIR/dmesg-err-warn.txt"
fi

# Per-failed-unit deep dump.
FAILED_UNITS_DIR="$SNAP_DIR/failed-units-deep"
mkdir -p "$FAILED_UNITS_DIR"
if command -v systemctl >/dev/null 2>&1; then
  mapfile -t failed_units < <(systemctl list-units --failed --no-legend --plain 2>/dev/null | awk 'NF{print $1}')
  if ((${#failed_units[@]} == 0)); then
    echo "no failed units in current state" > "$FAILED_UNITS_DIR/_none.txt"
  else
    for unit in "${failed_units[@]}"; do
      safe_unit="${unit//[^A-Za-z0-9_.-]/_}"
      systemctl cat "$unit" > "$FAILED_UNITS_DIR/${safe_unit}.cat.txt" 2>&1 || true
      systemctl status "$unit" --no-pager > "$FAILED_UNITS_DIR/${safe_unit}.status.txt" 2>&1 || true
      journalctl --since "$SINCE" -u "$unit" --no-pager > "$FAILED_UNITS_DIR/${safe_unit}.journal.txt" 2>&1 || true
    done
  fi
fi

# Pack to single archive for sharing; store relative path (no absolute host paths).
tar -C "$OUT_DIR" -czf "$ARCHIVE_PATH" "$(basename "$SNAP_DIR")"

echo "[OK] capstone snapshot created"
echo "[INFO] path: $SNAP_DIR"
echo "[INFO] archive: $ARCHIVE_PATH"
