#!/usr/bin/env bash
# Description: Validate loop filesystem/swap lab state and print useful diagnostics.
# Usage: check-storage-lab.sh [--strict]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  check-storage-lab.sh [--strict]

Examples:
  ./lessons/12-storage-filesystems-fstab-lvm/scripts/check-storage-lab.sh
  ./lessons/12-storage-filesystems-fstab-lvm/scripts/check-storage-lab.sh --strict
USAGE
}

STRICT=0
STATE_FILE="/tmp/lesson12_storage_state.env"

# Parse flags for help/strict mode.
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --strict)
      STRICT=1
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      usage
      exit 2
      ;;
  esac
done

# Ensure basic tools are available before running checks.
for cmd in sudo lsblk blkid findmnt df swapon; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: state file not found: $STATE_FILE" >&2
  echo "Run setup-storage-lab.sh first." >&2
  exit 1
fi

# Load state produced by setup script.
# shellcheck disable=SC1090
source "$STATE_FILE"

fail=0

# Print current tracked resources from state file.
echo "[INFO] loop device: ${LOOP_DEV:-<unknown>}"
echo "[INFO] mount point: ${MOUNT_POINT:-<unknown>}"
echo "[INFO] swap file: ${SWAP_FILE:-<unknown>}"

# Check that loop device still exists and has expected filesystem metadata.
echo
if [[ -n "${LOOP_DEV:-}" && -b "${LOOP_DEV}" ]]; then
  echo "[CHECK] loop device exists"
  lsblk -f "$LOOP_DEV" || true
  sudo blkid "$LOOP_DEV" || true
else
  echo "[WARN] loop device missing"
  fail=1
fi

# Check that filesystem is currently mounted at expected target.
echo
if [[ -n "${MOUNT_POINT:-}" ]] && findmnt -rn "$MOUNT_POINT" >/dev/null 2>&1; then
  echo "[CHECK] mount active"
  findmnt "$MOUNT_POINT"
  df -h "$MOUNT_POINT"
else
  echo "[WARN] mount not active"
  fail=1
fi

# Check that lesson swapfile is active.
echo
if [[ -n "${SWAP_FILE:-}" ]] && sudo swapon --show=NAME --noheadings | grep -Fxq "$SWAP_FILE"; then
  echo "[CHECK] swap active"
  sudo swapon --show | sed -n '1,20p'
else
  echo "[WARN] swap is not active"
  fail=1
fi

# Show tagged fstab lines if lab touched /etc/fstab.
echo
if [[ -n "${FSTAB_TAG:-}" ]]; then
  echo "[CHECK] fstab tagged entries"
  grep -n "$FSTAB_TAG" /etc/fstab || true
fi

# In strict mode, any failed check becomes a non-zero exit.
if (( STRICT && fail )); then
  echo "[FAIL] one or more checks failed" >&2
  exit 1
fi

echo "[OK] check completed"
