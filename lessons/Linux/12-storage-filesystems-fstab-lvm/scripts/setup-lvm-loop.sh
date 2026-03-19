#!/usr/bin/env bash
# Description: Build safe LVM lab on two loop devices (PV -> VG -> LV -> ext4 mount).
# Usage: setup-lvm-loop.sh [--lab-dir DIR] [--pv-size-mb N] [--lv-size-mb N] [--vg NAME] [--lv NAME] [--mount-point DIR]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  setup-lvm-loop.sh [--lab-dir DIR] [--pv-size-mb N] [--lv-size-mb N] [--vg NAME] [--lv NAME] [--mount-point DIR]

Defaults:
  --lab-dir /tmp/lesson12-lvm
  --pv-size-mb 192
  --lv-size-mb 256
  --vg vglesson12
  --lv lvdata
  --mount-point /mnt/lesson12-lvm

Examples:
  ./lessons/12-storage-filesystems-fstab-lvm/scripts/setup-lvm-loop.sh
  ./lessons/12-storage-filesystems-fstab-lvm/scripts/setup-lvm-loop.sh --pv-size-mb 256 --lv-size-mb 384
USAGE
}

LAB_DIR="/tmp/lesson12-lvm"
PV_SIZE_MB="192"
LV_SIZE_MB="256"
VG_NAME="vglesson12"
LV_NAME="lvdata"
MOUNT_POINT="/mnt/lesson12-lvm"
STATE_FILE="/tmp/lesson12_lvm_state.env"
SETUP_OK=0
LOOP1=""
LOOP2=""
MIN_HEADROOM_MB=16

# Fast help handling before full argument parsing.
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
    --pv-size-mb)
      [[ $# -ge 2 ]] || { echo "ERROR: --pv-size-mb requires value" >&2; exit 2; }
      PV_SIZE_MB="$2"
      shift 2
      ;;
    --lv-size-mb)
      [[ $# -ge 2 ]] || { echo "ERROR: --lv-size-mb requires value" >&2; exit 2; }
      LV_SIZE_MB="$2"
      shift 2
      ;;
    --vg)
      [[ $# -ge 2 ]] || { echo "ERROR: --vg requires value" >&2; exit 2; }
      VG_NAME="$2"
      shift 2
      ;;
    --lv)
      [[ $# -ge 2 ]] || { echo "ERROR: --lv requires value" >&2; exit 2; }
      LV_NAME="$2"
      shift 2
      ;;
    --mount-point)
      [[ $# -ge 2 ]] || { echo "ERROR: --mount-point requires value" >&2; exit 2; }
      MOUNT_POINT="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Validate numeric sizing parameters.
[[ "$PV_SIZE_MB" =~ ^[0-9]+$ ]] || { echo "ERROR: --pv-size-mb must be integer" >&2; exit 2; }
[[ "$LV_SIZE_MB" =~ ^[0-9]+$ ]] || { echo "ERROR: --lv-size-mb must be integer" >&2; exit 2; }

# We create two PV images, so total raw capacity is 2 * PV size.
TOTAL_PV_MB=$(( PV_SIZE_MB * 2 ))
# Keep small reserved headroom to avoid edge failures near full VG capacity.
MAX_SAFE_LV_MB=$(( TOTAL_PV_MB - MIN_HEADROOM_MB ))
if (( MAX_SAFE_LV_MB <= 0 )); then
  echo "ERROR: invalid PV sizing; total PV capacity too small" >&2
  exit 2
fi
if (( LV_SIZE_MB > MAX_SAFE_LV_MB )); then
  echo "ERROR: --lv-size-mb=$LV_SIZE_MB is too large for 2xPV=${TOTAL_PV_MB}MB" >&2
  echo "Keep at least ${MIN_HEADROOM_MB}MB headroom for metadata/alignment; max safe LV is ${MAX_SAFE_LV_MB}MB." >&2
  exit 2
fi

# Ensure required LVM and filesystem tools exist.
for cmd in sudo truncate losetup findmnt pvcreate pvremove vgcreate vgremove lvcreate lvremove lvdisplay vgdisplay mkfs.ext4 mount umount; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $cmd" >&2
    echo "Hint: install lvm2 if pvcreate/vgcreate/lvcreate are missing." >&2
    exit 1
  }
done

# Avoid clashing with existing VG on the host.
if sudo vgdisplay "$VG_NAME" >/dev/null 2>&1; then
  echo "ERROR: VG already exists: $VG_NAME" >&2
  echo "Run cleanup-lvm-loop.sh first or choose another --vg name." >&2
  exit 1
fi

# Prepare lab workspace and mount target.
mkdir -p "$LAB_DIR"
sudo mkdir -p "$MOUNT_POINT"
if findmnt -rn "$MOUNT_POINT" >/dev/null 2>&1; then
  echo "ERROR: mount point already in use: $MOUNT_POINT" >&2
  echo "Run cleanup-lvm-loop.sh first or choose another mount point." >&2
  exit 1
fi

PV1_IMG="$LAB_DIR/pv1.img"
PV2_IMG="$LAB_DIR/pv2.img"
# Refuse to reuse old images implicitly; user should cleanup first.
if [[ -e "$PV1_IMG" || -e "$PV2_IMG" ]]; then
  echo "ERROR: LVM lab image files already exist in $LAB_DIR" >&2
  echo "Run cleanup-lvm-loop.sh first or remove old images." >&2
  exit 1
fi
truncate -s "${PV_SIZE_MB}M" "$PV1_IMG"
truncate -s "${PV_SIZE_MB}M" "$PV2_IMG"

# Roll back partial resources if setup fails in the middle.
cleanup_on_error() {
  local rc="$?"
  if (( rc == 0 || SETUP_OK )); then
    return
  fi

  echo "[WARN] setup-lvm-loop failed (rc=$rc), running rollback cleanup" >&2

  if findmnt -rn "$MOUNT_POINT" >/dev/null 2>&1; then
    sudo umount "$MOUNT_POINT" 2>/dev/null || true
  fi

  if sudo lvdisplay "/dev/$VG_NAME/$LV_NAME" >/dev/null 2>&1; then
    sudo lvremove -y "/dev/$VG_NAME/$LV_NAME" >/dev/null 2>&1 || true
  fi

  # Remove VG only after LV removal attempt.
  if sudo vgdisplay "$VG_NAME" >/dev/null 2>&1; then
    sudo vgremove -y "$VG_NAME" >/dev/null 2>&1 || true
  fi

  # Detach loop devices last, after LVM metadata teardown.
  for dev in "$LOOP1" "$LOOP2"; do
    if [[ -n "$dev" && -b "$dev" ]]; then
      sudo pvremove -ff -y "$dev" >/dev/null 2>&1 || true
      sudo losetup -d "$dev" >/dev/null 2>&1 || true
    fi
  done

  rm -f "$STATE_FILE"
}

trap cleanup_on_error EXIT

# Attach each image to its own loop device (future PVs).
LOOP1="$(sudo losetup --find --show "$PV1_IMG")"
LOOP2="$(sudo losetup --find --show "$PV2_IMG")"

# Build full LVM stack on disposable loop devices.
sudo pvcreate -ff -y "$LOOP1" "$LOOP2" >/dev/null
sudo vgcreate "$VG_NAME" "$LOOP1" "$LOOP2" >/dev/null
sudo lvcreate -L "${LV_SIZE_MB}M" -n "$LV_NAME" "$VG_NAME" >/dev/null

LV_PATH="/dev/$VG_NAME/$LV_NAME"
# Create filesystem on LV and mount it for lab work.
sudo mkfs.ext4 -F "$LV_PATH" >/dev/null
sudo mount "$LV_PATH" "$MOUNT_POINT"
sudo chown "$(id -u):$(id -g)" "$MOUNT_POINT"
echo "lesson12 lvm lab: $(date +'%F %T')" > "$MOUNT_POINT/README.txt"

# Persist state so cleanup script can reverse all changes safely.
cat > "$STATE_FILE" <<STATE
LAB_DIR="$LAB_DIR"
PV1_IMG="$PV1_IMG"
PV2_IMG="$PV2_IMG"
LOOP1="$LOOP1"
LOOP2="$LOOP2"
VG_NAME="$VG_NAME"
LV_NAME="$LV_NAME"
LV_PATH="$LV_PATH"
MOUNT_POINT="$MOUNT_POINT"
STATE

echo "[OK] lvm lab is ready"
echo "[INFO] PV loops: $LOOP1 $LOOP2"
echo "[INFO] LV path: $LV_PATH"
echo "[INFO] mount point: $MOUNT_POINT"
echo "[INFO] state file: $STATE_FILE"

# Mark successful completion so EXIT trap won't rollback valid setup.
SETUP_OK=1
