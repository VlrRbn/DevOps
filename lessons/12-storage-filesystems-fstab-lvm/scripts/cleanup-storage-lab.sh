#!/usr/bin/env bash
# Description: Tear down loop filesystem/swap lab and optionally purge artifacts.
# Usage: cleanup-storage-lab.sh [--purge]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  cleanup-storage-lab.sh [--purge]

Defaults:
  --purge is ON (lab files are deleted)

Examples:
  ./lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-storage-lab.sh
  ./lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-storage-lab.sh --no-purge
USAGE
}

STATE_FILE="/tmp/lesson12_storage_state.env"
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

# If state is missing, try cleanup using default lesson paths.
if [[ ! -f "$STATE_FILE" ]]; then
  echo "[WARN] state file not found: $STATE_FILE"
  echo "[INFO] attempting cleanup by defaults"
  DEFAULT_LAB_DIR="/tmp/lesson12-storage"
  DEFAULT_IMG_FILE="$DEFAULT_LAB_DIR/disk.img"
  DEFAULT_SWAP_FILE="$DEFAULT_LAB_DIR/swapfile"
  DEFAULT_MOUNT_POINT="/mnt/lesson12-data"

  # Teardown order matters: swapoff -> umount -> detach loop.
  if sudo swapon --show=NAME --noheadings | grep -Fxq "$DEFAULT_SWAP_FILE"; then
    sudo swapoff "$DEFAULT_SWAP_FILE" || true
  fi
  if findmnt -rn "$DEFAULT_MOUNT_POINT" >/dev/null 2>&1; then
    sudo umount "$DEFAULT_MOUNT_POINT" || true
  fi
  while IFS= read -r line; do
    dev="${line%%:*}"
    [[ -n "$dev" ]] || continue
    sudo losetup -d "$dev" || true
  done < <(sudo losetup -j "$DEFAULT_IMG_FILE")

  # Remove only tagged lab entries from fstab.
  FSTAB_TAG="lesson12-storage-lab"
  if grep -Fq "$FSTAB_TAG" /etc/fstab; then
    sudo sed -i "/$FSTAB_TAG/d" /etc/fstab
    echo "[INFO] removed /etc/fstab tagged lines"
  fi
  exit 0
fi

# Load canonical state from setup run.
# shellcheck disable=SC1090
source "$STATE_FILE"

# Teardown order: disable swap first, then unmount, then detach loop.
if [[ -n "${SWAP_FILE:-}" ]] && sudo swapon --show=NAME --noheadings | grep -Fxq "$SWAP_FILE"; then
  sudo swapoff "$SWAP_FILE" || true
fi

if [[ -n "${MOUNT_POINT:-}" ]] && findmnt -rn "$MOUNT_POINT" >/dev/null 2>&1; then
  sudo umount "$MOUNT_POINT" || true
fi

if [[ -n "${LOOP_DEV:-}" ]] && [[ -b "$LOOP_DEV" ]]; then
  sudo losetup -d "$LOOP_DEV" || true
fi

# Remove tagged fstab lines if they were added by this lesson.
if [[ -n "${FSTAB_TAG:-}" ]] && grep -Fq "$FSTAB_TAG" /etc/fstab; then
  sudo sed -i "/$FSTAB_TAG/d" /etc/fstab
fi

# Optionally delete lab files/directories; keep them with --no-purge.
if (( PURGE )); then
  if [[ -n "${LAB_DIR:-}" && -d "$LAB_DIR" ]]; then
    rm -rf "$LAB_DIR"
  fi
  if [[ -n "${MOUNT_POINT:-}" && -d "$MOUNT_POINT" ]]; then
    rmdir "$MOUNT_POINT" 2>/dev/null || true
  fi
fi

# Remove state at the very end so subsequent cleanup can still use it on failures.
rm -f "$STATE_FILE"

echo "[OK] storage lab cleanup completed"
