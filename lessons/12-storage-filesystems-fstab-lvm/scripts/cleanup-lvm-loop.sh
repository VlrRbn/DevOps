#!/usr/bin/env bash
# Description: Remove LVM loop lab created by setup-lvm-loop.sh.
# Usage: cleanup-lvm-loop.sh [--purge]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  cleanup-lvm-loop.sh [--purge]

Defaults:
  --purge is ON (image files are deleted)

Examples:
  ./lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-lvm-loop.sh
  ./lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-lvm-loop.sh --no-purge
USAGE
}

STATE_FILE="/tmp/lesson12_lvm_state.env"
PURGE=1

# Parse cleanup mode flags.
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --purge)
      PURGE=1
      ;;
    --no-purge)
      PURGE=0
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      usage
      exit 2
      ;;
  esac
done

# Without state, there is no reliable target set for cleanup.
if [[ ! -f "$STATE_FILE" ]]; then
  echo "[WARN] state file not found: $STATE_FILE"
  exit 0
fi

# Load setup metadata for deterministic teardown.
# shellcheck disable=SC1090
source "$STATE_FILE"

# Teardown order: unmount -> remove LV -> remove VG -> detach loop devices.
if [[ -n "${MOUNT_POINT:-}" ]] && findmnt -rn "$MOUNT_POINT" >/dev/null 2>&1; then
  sudo umount "$MOUNT_POINT" || true
fi

if [[ -n "${VG_NAME:-}" && -n "${LV_NAME:-}" ]] && sudo lvdisplay "/dev/$VG_NAME/$LV_NAME" >/dev/null 2>&1; then
  sudo lvremove -y "/dev/$VG_NAME/$LV_NAME" >/dev/null || true
fi

if [[ -n "${VG_NAME:-}" ]] && sudo vgdisplay "$VG_NAME" >/dev/null 2>&1; then
  sudo vgremove -y "$VG_NAME" >/dev/null || true
fi

for dev in "${LOOP1:-}" "${LOOP2:-}"; do
  if [[ -n "$dev" && -b "$dev" ]]; then
    sudo pvremove -ff -y "$dev" >/dev/null 2>&1 || true
    sudo losetup -d "$dev" >/dev/null 2>&1 || true
  fi
done

# Optional artifact purge; keep images when --no-purge is used.
if (( PURGE )); then
  if [[ -n "${LAB_DIR:-}" && -d "$LAB_DIR" ]]; then
    rm -rf "$LAB_DIR"
  fi
  if [[ -n "${MOUNT_POINT:-}" && -d "$MOUNT_POINT" ]]; then
    rmdir "$MOUNT_POINT" 2>/dev/null || true
  fi
fi

# Remove state file only after all cleanup steps complete.
rm -f "$STATE_FILE"

echo "[OK] lvm lab cleanup completed"
