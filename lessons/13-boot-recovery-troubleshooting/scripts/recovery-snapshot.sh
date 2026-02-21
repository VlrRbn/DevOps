#!/usr/bin/env bash
# Description: Save a recovery snapshot (configs + boot diagnostics + failed-unit deep dump) and archive it.
# Usage: recovery-snapshot.sh [--out-dir DIR]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  recovery-snapshot.sh [--out-dir DIR]

Defaults:
  --out-dir /tmp

Examples:
  ./lessons/13-boot-recovery-troubleshooting/scripts/recovery-snapshot.sh
  ./lessons/13-boot-recovery-troubleshooting/scripts/recovery-snapshot.sh --out-dir /tmp/lesson13-artifacts
USAGE
}

OUT_DIR="/tmp"

# Parse supported CLI options.
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
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Validate required tools up front.
for cmd in mkdir cp hostname uname date lsblk blkid findmnt journalctl systemctl tar basename dmesg; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

# Build deterministic snapshot directory and archive names.
STAMP="$(date +%Y%m%d_%H%M%S)"
SNAP_DIR="$OUT_DIR/recovery-snapshot_${STAMP}"
ARCHIVE_PATH="${SNAP_DIR}.tar.gz"
mkdir -p "$SNAP_DIR"

# Use passwordless sudo when available for richer diagnostics.
SUDO_CMD=()
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  SUDO_CMD=(sudo -n)
fi

# Save critical config files often involved in boot issues.
for file in /etc/fstab /etc/default/grub /etc/nftables.conf; do
  if [[ -f "$file" ]]; then
    cp -a "$file" "$SNAP_DIR/"
  fi
done

if [[ -d /etc/systemd/system ]]; then
  mkdir -p "$SNAP_DIR/systemd"
  # Capture local unit overrides/custom units that often break boot flows.
  cp -a /etc/systemd/system/*.service "$SNAP_DIR/systemd/" 2>/dev/null || true
  cp -a /etc/systemd/system/*.mount "$SNAP_DIR/systemd/" 2>/dev/null || true
  cp -a /etc/systemd/system/*.timer "$SNAP_DIR/systemd/" 2>/dev/null || true
  cp -a /etc/systemd/system/*.target "$SNAP_DIR/systemd/" 2>/dev/null || true
fi

# Capture runtime diagnostics for later offline analysis.
{
  echo "timestamp=$(date '+%F %T')"
  echo "host=$(hostname)"
  echo "kernel=$(uname -a)"
} > "$SNAP_DIR/meta.txt"

lsblk -f > "$SNAP_DIR/lsblk-f.txt" 2>&1 || true
# blkid may need elevated privileges on some hosts.
if ((${#SUDO_CMD[@]} > 0)); then
  "${SUDO_CMD[@]}" blkid > "$SNAP_DIR/blkid.txt" 2>&1 || true
else
  blkid > "$SNAP_DIR/blkid.txt" 2>&1 || true
fi
findmnt -A > "$SNAP_DIR/findmnt-A.txt" 2>&1 || true
findmnt --verify > "$SNAP_DIR/findmnt-verify.txt" 2>&1 || true
systemctl is-system-running > "$SNAP_DIR/system-state.txt" 2>&1 || true
systemctl list-units --failed --no-pager --plain > "$SNAP_DIR/failed-units.txt" 2>&1 || true
journalctl -b -p err..alert --no-pager > "$SNAP_DIR/journal-err-alert.txt" 2>&1 || true
journalctl -b --no-pager | tail -n 300 > "$SNAP_DIR/journal-tail300.txt" 2>&1 || true

# Kernel-level warnings/errors for boot incident context.
if ((${#SUDO_CMD[@]} > 0)); then
  "${SUDO_CMD[@]}" dmesg --level=err,warn > "$SNAP_DIR/dmesg-err-warn.txt" 2>&1 || true
else
  dmesg --level=err,warn > "$SNAP_DIR/dmesg-err-warn.txt" 2>&1 || true
fi

# For every failed unit, save effective unit file + boot log stream for that unit.
FAILED_UNITS_DIR="$SNAP_DIR/failed-units"
mkdir -p "$FAILED_UNITS_DIR"
mapfile -t failed_units < <(systemctl list-units --failed --no-legend --plain | awk 'NF{print $1}')

if ((${#failed_units[@]} == 0)); then
  echo "no failed units in current state" > "$FAILED_UNITS_DIR/_none.txt"
else
  for unit in "${failed_units[@]}"; do
    # Sanitize unit name for portable filenames.
    safe_unit="${unit//[^A-Za-z0-9_.-]/_}"
    systemctl cat "$unit" > "$FAILED_UNITS_DIR/${safe_unit}.cat.txt" 2>&1 || true
    systemctl status "$unit" --no-pager > "$FAILED_UNITS_DIR/${safe_unit}.status.txt" 2>&1 || true
    journalctl -b -u "$unit" --no-pager > "$FAILED_UNITS_DIR/${safe_unit}.journal-b.txt" 2>&1 || true
  done
fi

if [[ -r /proc/cmdline ]]; then
  cp -a /proc/cmdline "$SNAP_DIR/proc-cmdline.txt"
fi

# Pack snapshot directory into a single archive for transfer/attachment.
tar -C "$OUT_DIR" -czf "$ARCHIVE_PATH" "$(basename "$SNAP_DIR")"

echo "[OK] recovery snapshot created"
echo "[INFO] path: $SNAP_DIR"
echo "[INFO] archive: $ARCHIVE_PATH"
