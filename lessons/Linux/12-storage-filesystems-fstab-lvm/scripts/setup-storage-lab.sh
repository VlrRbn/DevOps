#!/usr/bin/env bash
# Description: Create a safe loop-backed ext4 + swap lab for lesson 12.
# Usage: setup-storage-lab.sh [--lab-dir DIR] [--img-size-mb N] [--swap-size-mb N] [--mount-point DIR] [--write-fstab] [--force]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  setup-storage-lab.sh [--lab-dir DIR] [--img-size-mb N] [--swap-size-mb N] [--mount-point DIR] [--write-fstab] [--force]

Defaults:
  --lab-dir /tmp/lesson12-storage
  --img-size-mb 256
  --swap-size-mb 128
  --mount-point /mnt/lesson12-data

Examples:
  ./lessons/12-storage-filesystems-fstab-lvm/scripts/setup-storage-lab.sh
  ./lessons/12-storage-filesystems-fstab-lvm/scripts/setup-storage-lab.sh --img-size-mb 512 --swap-size-mb 256
  ./lessons/12-storage-filesystems-fstab-lvm/scripts/setup-storage-lab.sh --write-fstab
  ./lessons/12-storage-filesystems-fstab-lvm/scripts/setup-storage-lab.sh --force
USAGE
}

LAB_DIR="/tmp/lesson12-storage"
IMG_SIZE_MB="256"
SWAP_SIZE_MB="128"
MOUNT_POINT="/mnt/lesson12-data"
WRITE_FSTAB=0
FORCE=0
STATE_FILE="/tmp/lesson12_storage_state.env"
FSTAB_TAG="lesson12-storage-lab"
SETUP_OK=0
FSTAB_APPENDED=0
LOOP_DEV=""

# Fast-path help flag before full argument parsing.
for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    usage
    exit 0
  fi
done

# Parse supported CLI options.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lab-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --lab-dir requires value" >&2; exit 2; }
      LAB_DIR="$2"
      shift 2
      ;;
    --img-size-mb)
      [[ $# -ge 2 ]] || { echo "ERROR: --img-size-mb requires value" >&2; exit 2; }
      IMG_SIZE_MB="$2"
      shift 2
      ;;
    --swap-size-mb)
      [[ $# -ge 2 ]] || { echo "ERROR: --swap-size-mb requires value" >&2; exit 2; }
      SWAP_SIZE_MB="$2"
      shift 2
      ;;
    --mount-point)
      [[ $# -ge 2 ]] || { echo "ERROR: --mount-point requires value" >&2; exit 2; }
      MOUNT_POINT="$2"
      shift 2
      ;;
    --write-fstab)
      WRITE_FSTAB=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Basic input validation for numeric knobs.
[[ "$IMG_SIZE_MB" =~ ^[0-9]+$ ]] || { echo "ERROR: --img-size-mb must be integer" >&2; exit 2; }
[[ "$SWAP_SIZE_MB" =~ ^[0-9]+$ ]] || { echo "ERROR: --swap-size-mb must be integer" >&2; exit 2; }

# Validate runtime dependencies once, fail early if something is missing.
for cmd in sudo truncate dd losetup mkfs.ext4 mount umount findmnt blkid mkswap swapon swapoff chown chmod; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

IMG_FILE="$LAB_DIR/disk.img"
SWAP_FILE="$LAB_DIR/swapfile"
FSTAB_EXAMPLE="$LAB_DIR/fstab.example"

# Roll back partially-created resources if setup fails mid-run.
cleanup_on_error() {
  local rc="$?"
  if (( rc == 0 || SETUP_OK )); then
    return
  fi

  echo "[WARN] setup failed (rc=$rc), running rollback cleanup" >&2

  if sudo swapon --show=NAME --noheadings | grep -Fxq "$SWAP_FILE"; then
    sudo swapoff "$SWAP_FILE" 2>/dev/null || true
  fi

  if findmnt -rn "$MOUNT_POINT" >/dev/null 2>&1; then
    sudo umount "$MOUNT_POINT" 2>/dev/null || true
  fi

  if [[ -n "$LOOP_DEV" && -b "$LOOP_DEV" ]]; then
    sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
  fi

  if (( FSTAB_APPENDED )); then
    sudo sed -i "/$FSTAB_TAG/d" /etc/fstab 2>/dev/null || true
  fi
}

trap cleanup_on_error EXIT

# Ensure local working dir exists and create privileged mount point path.
mkdir -p "$LAB_DIR"
sudo mkdir -p "$MOUNT_POINT"

# Refuse accidental overwrite unless user explicitly asked for --force.
if (( ! FORCE )); then
  if [[ -e "$IMG_FILE" || -e "$SWAP_FILE" || -e "$FSTAB_EXAMPLE" ]]; then
    echo "ERROR: lab files already exist in $LAB_DIR" >&2
    echo "Run cleanup script first or use --force to overwrite." >&2
    exit 1
  fi
fi

# Mountpoint must not already be in use.
if findmnt -rn "$MOUNT_POINT" >/dev/null 2>&1; then
  echo "ERROR: mount point already in use: $MOUNT_POINT" >&2
  echo "Run cleanup script first or choose another mount point." >&2
  exit 1
fi

# Guard against stale loop/swap usage from previous failed/manual runs.
if sudo losetup -j "$IMG_FILE" | grep -q .; then
  if (( ! FORCE )); then
    echo "ERROR: image is already attached to a loop device: $IMG_FILE" >&2
    echo "Run cleanup script first or use --force to detach stale loop." >&2
    exit 1
  fi
  while IFS= read -r line; do
    dev="${line%%:*}"
    [[ -n "$dev" ]] || continue
    sudo losetup -d "$dev" || true
  done < <(sudo losetup -j "$IMG_FILE")
fi

if sudo swapon --show=NAME --noheadings | grep -Fxq "$SWAP_FILE"; then
  if (( ! FORCE )); then
    echo "ERROR: swapfile is active: $SWAP_FILE" >&2
    echo "Run cleanup script first or use --force to swapoff stale entry." >&2
    exit 1
  fi
  sudo swapoff "$SWAP_FILE" || true
fi

# Start from a fresh image file, then bind it to a loop device.
rm -f "$IMG_FILE" "$FSTAB_EXAMPLE"
truncate -s "${IMG_SIZE_MB}M" "$IMG_FILE"
LOOP_DEV="$(sudo losetup --find --show "$IMG_FILE")"

# Build a clean ext4 filesystem on top of loop device.
sudo mkfs.ext4 -F -L LESSON12_DATA "$LOOP_DEV" >/dev/null
sudo mount "$LOOP_DEV" "$MOUNT_POINT"
sudo chown "$(id -u):$(id -g)" "$MOUNT_POINT"
echo "lesson12 storage lab: $(date +'%F %T')" > "$MOUNT_POINT/README.txt"

# Recreate swapfile safely: non-sparse, root-owned, strict permissions.
sudo rm -f "$SWAP_FILE"
# Use dd (not truncate) to avoid sparse swapfile with holes.
sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=none
sudo chown root:root "$SWAP_FILE"
sudo chmod 600 "$SWAP_FILE"
sudo mkswap "$SWAP_FILE" >/dev/null
if ! sudo swapon --show=NAME --noheadings | grep -Fxq "$SWAP_FILE"; then
  sudo swapon "$SWAP_FILE"
fi

# Collect UUID for stable fstab-style references.
FS_UUID="$(sudo blkid -s UUID -o value "$LOOP_DEV")"

# Write an example fstab snippet to review before applying.
cat > "$FSTAB_EXAMPLE" <<EXAMPLE
# Example lines for lesson 12 (review before apply):
UUID=$FS_UUID $MOUNT_POINT ext4 defaults,nofail,noatime 0 2
$SWAP_FILE none swap sw 0 0
EXAMPLE

# Optionally append tagged lab entries to /etc/fstab.
if (( WRITE_FSTAB )); then
  if ! grep -Fq "$FSTAB_TAG" /etc/fstab; then
    {
      echo "UUID=$FS_UUID $MOUNT_POINT ext4 defaults,nofail,noatime 0 2 # $FSTAB_TAG"
      echo "$SWAP_FILE none swap sw 0 0 # $FSTAB_TAG"
    } | sudo tee -a /etc/fstab >/dev/null
    FSTAB_APPENDED=1
  fi
fi

# Persist setup state for check/cleanup scripts.
cat > "$STATE_FILE" <<STATE
LAB_DIR="$LAB_DIR"
IMG_FILE="$IMG_FILE"
LOOP_DEV="$LOOP_DEV"
MOUNT_POINT="$MOUNT_POINT"
SWAP_FILE="$SWAP_FILE"
FSTAB_TAG="$FSTAB_TAG"
STATE

echo "[OK] storage lab is ready"
echo "[INFO] loop device: $LOOP_DEV"
echo "[INFO] mount point: $MOUNT_POINT"
echo "[INFO] swap file: $SWAP_FILE"
echo "[INFO] state file: $STATE_FILE"
echo "[INFO] fstab example: $FSTAB_EXAMPLE"
if (( WRITE_FSTAB )); then
  echo "[INFO] /etc/fstab lines tagged with: $FSTAB_TAG"
else
  echo "[INFO] /etc/fstab not modified (use --write-fstab if you want to append lab lines)."
fi

# Mark setup success so EXIT trap will not rollback.
SETUP_OK=1
