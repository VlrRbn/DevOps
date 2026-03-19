# Storage/Filesystem Scripts (Lesson 12)

This folder contains helper scripts for lesson 12 (`loop` filesystem lab, `fstab`, swap, and optional LVM on loop devices).

## Files

- `setup-storage-lab.sh`
  - creates loop-backed ext4 filesystem and mounts it
  - creates non-sparse lab swap file (via `dd`) with `root:root` owner and enables it
  - writes `/tmp/lesson12_storage_state.env`
  - has rollback cleanup on setup failure (unmount/swapoff/loop detach)
  - refuses overwriting existing lab files unless `--force` is used
  - optional `--write-fstab` appends tagged lab entries to `/etc/fstab`
- `check-storage-lab.sh`
  - prints lab state (`lsblk`, `blkid`, mount, swap, tagged fstab lines)
  - `--strict` returns non-zero if any check fails
- `cleanup-storage-lab.sh`
  - disables swap, unmounts, detaches loop, removes tagged `/etc/fstab` lines
  - if state file is missing, runs best-effort cleanup for default lab paths
- `setup-lvm-loop.sh`
  - advanced lab: creates 2 loop PVs -> VG -> LV -> ext4 mount
  - validates size safety (keeps headroom; avoids edge-case LV sizing failures)
  - has rollback cleanup on setup failure (umount/lvremove/vgremove/pvremove/loop detach)
  - refuses run if mountpoint is already in use or old image files already exist
  - writes `/tmp/lesson12_lvm_state.env`
- `cleanup-lvm-loop.sh`
  - tears down advanced LVM loop lab

## Requirements

Core:

- `bash`, `sudo`
- `truncate`, `losetup`, `mkfs.ext4`, `mount`, `umount`, `findmnt`, `blkid`
- `mkswap`, `swapon`, `swapoff`

Advanced (LVM lab):

- `lvm2` tools: `pvcreate`, `vgcreate`, `lvcreate`, `lvremove`, `vgremove`, `pvremove`

## Usage

From repo root:

```bash
chmod +x lessons/12-storage-filesystems-fstab-lvm/scripts/*.sh

# Core lab
lessons/12-storage-filesystems-fstab-lvm/scripts/setup-storage-lab.sh
lessons/12-storage-filesystems-fstab-lvm/scripts/check-storage-lab.sh
lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-storage-lab.sh

# Advanced LVM lab
lessons/12-storage-filesystems-fstab-lvm/scripts/setup-lvm-loop.sh
lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-lvm-loop.sh
```

## Safety Notes

- Scripts are designed for disposable loop-backed labs and should not touch real disk partitions.
- `--write-fstab` appends lines tagged `lesson12-storage-lab`; cleanup removes tagged lines.
- Review `/etc/fstab` before reboot if you used `--write-fstab`.
