# lesson_12

# Storage and Filesystems: `mount`, `fstab`, `fsck`, `swap`, `LVM`

**Date:** 2026-02-19
**Topic:** safe storage operations with loop-backed labs: filesystems, mounts, swap, and LVM.  
**Daily goal:** Learn how to build and operate a storage stack safely, with verifiable checks and clean rollback.

---

## 0. Prerequisites

Check base dependencies:

```bash
command -v lsblk blkid findmnt mount umount losetup mkfs.ext4 fsck.ext4 swapon swapoff mkswap
```

For advanced LVM section:

```bash
command -v pvcreate vgcreate lvcreate pvs vgs lvs || echo "install lvm2 for advanced part"
```

Critical safety rule for this lesson:

- use only loop-backed files under `/tmp/lesson12-*`;
- do not format real `/dev/sdX` or `/dev/nvme...` devices;
- edit `/etc/fstab` only after backup and only with tagged lines.

---

## 1. Core Concepts

### 1.1 Block device -> filesystem -> mount point

The chain is always the same:

- block device exists (`/dev/loopX`, `/dev/sdb1`, `/dev/mapper/vg-lv`);
- filesystem is created on top (`ext4`, `xfs`);
- filesystem is mounted into a directory (`/mnt/data`).

Without `mount`, filesystem exists but is not attached to your directory tree.

### 1.2 Why UUID is better than `/dev/sdX`

Device names can change after reboot/hardware changes. UUID is stable.

That is why persistent entries in `/etc/fstab` usually use `UUID=...`, not `/dev/sdb1`.

### 1.3 What `/etc/fstab` does

`fstab` is a declaration of persistent mount/swap entries.

Line fields:

1. `device` (`UUID=...`, `LABEL=...`, `/path/to/swapfile`)
2. `mountpoint` (or `none` for swap)
3. `fstype` (`ext4`, `xfs`, `swap`)
4. `options` (`defaults`, `nofail`, `noatime`, ...)
5. `dump` (usually `0`)
6. `pass` (`1` root fs, `2` other fs, `0` skip fsck)

### 1.4 What `fsck` is and when to run it

`fsck` checks and repairs filesystem consistency.

Key rule:

- do not run repair on a read-write mounted filesystem;
- use safe preview (`-n`) or run after unmount.

### 1.5 Why swap matters

Swap is not "slow RAM", but it:

- helps survive memory spikes;
- stabilizes host behavior under pressure;
- can delay hard OOM scenarios.

In this lesson we use swapfile, not swap partition.

### 1.6 LVM model

LVM layers:

- `PV` (physical volume) — underlying block devices;
- `VG` (volume group) — capacity pool;
- `LV` (logical volume) — logical devices for filesystems.

Practical value: flexible resizing without repartitioning pain.

### 1.6.1 What the real flow looks like

Minimal lifecycle:

```bash
sudo pvcreate /dev/loopA /dev/loopB
sudo vgcreate vglesson12 /dev/loopA /dev/loopB
sudo lvcreate -L 256M -n lvdata vglesson12
sudo mkfs.ext4 /dev/vglesson12/lvdata
sudo mount /dev/vglesson12/lvdata /mnt/lesson12-lvm

pv1.img (file) → /dev/loopX → PV
pv2.img (file) → /dev/loopY → PV
PV + PV → VG (vglesson12)
VG → LV (lvdata) = /dev/vglesson12/lvdata
LV → ext4
ext4 → mount /mnt/lesson12-lvm
```

What matters here:

- `PV` turns a device into an LVM member;
- `VG` combines multiple PVs into one capacity pool;
- `LV` allocates logical volumes from that pool, effectively virtual disks for filesystems.

### 1.6.2 What you actually scale in production

In practice you usually scale the LVM layer, not raw partitions:

1. add capacity to VG (new PV or bigger PV);
2. extend LV (`lvextend`);
3. grow filesystem (often directly via `lvextend -r`).

So scaling is done through LVM abstractions instead of manual repartitioning.

### 1.6.3 How to read `pvs` / `vgs` / `lvs` quickly

- `pvs` shows which devices back LVM and free space per PV;
- `vgs` shows total/free capacity in the pool;
- `lvs` shows logical volume sizes and mapped devices.

Quick rule:

- if `vgs` has no `VFree`, `lvextend` cannot grow;
- if LV grew but `df` did not, filesystem was not resized.

### 1.6.4 Common mistakes

- formatting source loop/PV instead of the LV;
- sizing LV too close to total VG size and hitting metadata/alignment limits;
- skipping `findmnt` check and writing data to plain directory instead of mounted LV.

### 1.7 Safe ops workflow

For storage tasks, keep this sequence:

1. `read` state (`lsblk`, `findmnt`, `blkid`);
2. `change` (format/mount/swap/fstab);
3. `verify` (`findmnt`, `swapon --show`, `mount -a`);
4. `cleanup`/rollback.

---

## 2. Command Priority (What to Learn First)

### Core (must know now)

- `lsblk -f`
- `blkid`
- `mount` / `umount`
- `findmnt`
- `cat /etc/fstab`
- `mount -a` (validate `fstab`)
- `mkswap`, `swapon`, `swapoff`, `swapon --show`
- `fsck.ext4 -n`

### Optional (after core)

- `df -hT`, `du -sh`
- `findmnt -o SOURCE,TARGET,FSTYPE,OPTIONS`
- `tune2fs -l`
- `pvs`, `vgs`, `lvs`

### Advanced (ops-grade)

- rollback-safe `/etc/fstab` edits
- LVM lifecycle: create -> extend -> verify
- troubleshooting "fails to mount after reboot"
- runbook: symptom -> check -> action

---

## 3. Core Commands: What / Why / When

### `lsblk -f`

- **What:** block-device tree and filesystem info.
- **Why:** map storage quickly before changes.
- **When:** first command in any storage task.

```bash
lsblk -f
```

### `blkid`

- **What:** UUID/LABEL/FSTYPE metadata.
- **Why:** use stable IDs in `fstab`.
- **When:** before adding persistent mount entries.

```bash
sudo blkid
```

### `mount` + `findmnt`

- **What:** mount filesystem and verify immediately.
- **Why:** confirm actual mount state, not assumptions.
- **When:** right after `mkfs`.

```bash
sudo mount /dev/loopX /mnt/lesson12-data
findmnt /mnt/lesson12-data
```

### `umount`

- **What:** detach filesystem cleanly.
- **Why:** required before detach/fsck-repair.
- **When:** cleanup and maintenance.

```bash
sudo umount /mnt/lesson12-data
```

### Validate `/etc/fstab` with `mount -a`

- **What:** apply/test `fstab` entries and show errors now.
- **Why:** catch mistakes before reboot.
- **When:** after any `fstab` edit.

```bash
sudo mount -a
```

### `mkswap` + `swapon` + `swapoff`

- **What:** swapfile lifecycle.
- **Why:** controlled swap management without partitions.
- **When:** adding/testing/removing swap.

```bash
sudo dd if=/dev/zero of=/tmp/lesson12-storage/swapfile bs=1M count=128 status=none
sudo chown root:root /tmp/lesson12-storage/swapfile
sudo chmod 600 /tmp/lesson12-storage/swapfile
sudo mkswap /tmp/lesson12-storage/swapfile
sudo swapon /tmp/lesson12-storage/swapfile
swapon --show
sudo swapoff /tmp/lesson12-storage/swapfile
```

### `fsck.ext4 -n`

- **What:** dry-run consistency check (no writes).
- **Why:** safe first look at filesystem health.
- **When:** triage and pre-maintenance.

```bash
sudo fsck.ext4 -n "$LOOP_DEV"
```

---

## 4. Optional Commands (After Core)

Optional here means deeper visibility and better diagnostics.

### 4.1 `df -hT` + `du -sh`

- **What:** capacity from two angles: filesystem and directory usage.
- **Why:** quickly separate "disk full" vs "specific path grew".
- **When:** disk alerts and triage.

```bash
df -hT
sudo du -sh /var/log /var/lib 2>/dev/null
```

### 4.2 `findmnt -o SOURCE,TARGET,FSTYPE,OPTIONS`

- **What:** exact mount source/type/options.
- **Why:** verify options like `noatime`, `rw`, etc.
- **When:** after mount and after `mount -a`.

```bash
findmnt -o SOURCE,TARGET,FSTYPE,OPTIONS /mnt/lesson12-data
```

### 4.3 `tune2fs -l`

- **What:** ext4 metadata (state, reserved blocks, counters).
- **Why:** better understanding of fs behavior.
- **When:** deeper diagnostics and baseline capture.

```bash
sudo tune2fs -l /dev/loopX | sed -n '1,40p'
```

### 4.4 `pvs`, `vgs`, `lvs`

- **What:** LVM state at each layer.
- **Why:** identify where capacity limits are.
- **When:** after setup/resize operations.

```bash
sudo pvs
sudo vgs
sudo lvs -a -o +devices
```

### What to do in Optional in practice

1. Capture `df -hT` and `du -sh` baseline.
2. Verify active mounts with `findmnt`.
3. Inspect top ext4 metadata via `tune2fs -l`.
4. If using LVM, compare `pvs/vgs/lvs` before/after changes.

---

## 5. Advanced Topics (Ops-Grade)

### 5.1 Safe `/etc/fstab` editing pattern

Reliable pattern:

1. backup current file;
2. append only tagged lines;
3. run `mount -a`;
4. if error: remove tagged lines only and retest.

```bash
sudo cp -a /etc/fstab /etc/fstab.bak.$(date +%F_%H%M%S)
# edit / append lines
sudo mount -a
```

### 5.2 LVM lifecycle: extending logical volume

If VG has free extents, extend LV and filesystem in one go (`-r`):

```bash
sudo lvextend -L +64M -r /dev/vglesson12/lvdata
```

This is a common pattern for online growth.

### 5.3 Why mount can fail after reboot

Common causes:

- wrong UUID in `fstab`;
- typo in `fstype/options`;
- missing device at boot, no `nofail`;
- duplicate/conflicting entries.

Fast triage:

1. `lsblk -f` + `blkid` for actual IDs;
2. compare against `/etc/fstab`;
3. run `mount -a` and read exact error;
4. rollback tagged lines.

### 5.4 `fsck`: preview vs repair

- `-n` = check only;
- `-y` = auto-fix (maintenance window only);
- run repair on unmounted filesystem.

### 5.5 Symptom to action map

| Symptom | Check | Typical cause | Action |
|---|---|---|---|
| mount fails | `findmnt`, `dmesg`, `blkid` | wrong type/UUID | fix command or `fstab` entry |
| swap won't activate | `swapon --show`, `ls -lh`, perms/owner | sparse swapfile (after `truncate`) or non-root owner | recreate with `dd`, set `root:root`, `chmod 600`, then `mkswap` + `swapon` |
| volume "disappeared" | `pvs/vgs/lvs` | LVM sequence issue | verify VG/LV lifecycle order |
| `mount -a` errors | stderr output | `fstab` syntax/logic error | rollback tagged entries |

### 5.6 Why cleanup-on-error is required even for labs

In storage labs, a mid-run failure often leaves leftovers:

- mounted filesystem (`/mnt/...`);
- attached loop device;
- active swapfile.

That is why setup scripts should include rollback (`trap ... EXIT`): if a step fails, run `swapoff -> umount -> losetup -d` and clean temporary state.
This keeps reruns predictable.

---

## 6. Scripts in This Lesson

### 6.1 Manual Core run (do once without scripts)

```bash
# 1) prepare loop image
sudo mkdir -p /tmp/lesson12-storage /mnt/lesson12-data
truncate -s 256M /tmp/lesson12-storage/disk.img
LOOP_DEV="$(sudo losetup --find --show /tmp/lesson12-storage/disk.img)"

# 2) ext4 + mount
sudo mkfs.ext4 -F "$LOOP_DEV"
sudo mount "$LOOP_DEV" /mnt/lesson12-data
findmnt /mnt/lesson12-data

# check loop
losetup -a | grep /tmp/lesson12-storage/disk.img
lsblk -f "$LOOP_DEV"

# 3) swapfile (use dd to avoid sparse holes)
sudo dd if=/dev/zero of=/tmp/lesson12-storage/swapfile bs=1M count=128 status=none
sudo chown root:root /tmp/lesson12-storage/swapfile
sudo chmod 600 /tmp/lesson12-storage/swapfile
sudo mkswap /tmp/lesson12-storage/swapfile
sudo swapon /tmp/lesson12-storage/swapfile
swapon --show

# 4) fstab example (first in a file)
sudo blkid "$LOOP_DEV"
cat > /tmp/lesson12-storage/fstab.example <<'EOT'
UUID=<PUT_UUID_HERE> /mnt/lesson12-data ext4 defaults,nofail,noatime 0 2
/tmp/lesson12-storage/swapfile none swap sw 0 0
EOT

# read/write test
sudo sh -c 'echo "ok $(date)" > /mnt/lesson12-data/healthcheck.txt'
sudo cat /mnt/lesson12-data/healthcheck.txt
sync

# 5) cleanup
sudo swapoff /tmp/lesson12-storage/swapfile
sudo umount /mnt/lesson12-data
sudo losetup -d "$LOOP_DEV"
```

### 6.2 Scripts (automation)

```bash
chmod +x lessons/12-storage-filesystems-fstab-lvm/scripts/*.sh

# core
lessons/12-storage-filesystems-fstab-lvm/scripts/setup-storage-lab.sh
lessons/12-storage-filesystems-fstab-lvm/scripts/check-storage-lab.sh
lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-storage-lab.sh

# advanced lvm
lessons/12-storage-filesystems-fstab-lvm/scripts/setup-lvm-loop.sh
lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-lvm-loop.sh
```

### 6.3 Difference between `setup-storage-lab.sh` and `setup-lvm-loop.sh`

| Script | Layout | What it gives | When to use |
|---|---|---|---|
| `setup-storage-lab.sh` | `loop -> ext4` + `swapfile` | minimal layers, fast and clear base flow | core practice for `mount/fstab/swap` |
| `setup-lvm-loop.sh` | `loop -> PV -> VG -> LV -> ext4` | pooled capacity and controlled volume growth (`lvextend`) | advanced practice and LVM workflows |

Key idea:

- in the first script, filesystem sits directly on loop device;
- in the second, filesystem sits on an `LV` allocated from a `VG` built from multiple `PV`s.

What scripts automate:

- reproducible loop-based storage lab;
- state files under `/tmp/lesson12_*_state.env`;
- tagged cleanup for safe `fstab` rollback.

---

## 7. Mini Lab (Core Path)

Goal: build ext4+swap lab, validate state, cleanly tear it down.

```bash
# setup
lessons/12-storage-filesystems-fstab-lvm/scripts/setup-storage-lab.sh

# checks
lessons/12-storage-filesystems-fstab-lvm/scripts/check-storage-lab.sh --strict

# quick manual verify
findmnt /mnt/lesson12-data
swapon --show

# cleanup
lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-storage-lab.sh
```

Success criteria:

- mountpoint is active during setup phase;
- swapfile appears in `swapon --show`;
- after cleanup there is no lab mount/swap/loop left.

---

## 8. Extended Lab (Optional + Advanced)

### 8.1 Tagged `fstab` workflow

```bash
lessons/12-storage-filesystems-fstab-lvm/scripts/setup-storage-lab.sh --write-fstab
sudo grep -n "lesson12-storage-lab" /etc/fstab
sudo mount -a
lessons/12-storage-filesystems-fstab-lvm/scripts/check-storage-lab.sh
```

### 8.2 LVM on loop devices

```bash
lessons/12-storage-filesystems-fstab-lvm/scripts/setup-lvm-loop.sh
sudo pvs
sudo vgs
sudo lvs -a -o +devices
findmnt /mnt/lesson12-lvm
```

### 8.3 Extend LV (if VG has free space)

```bash
sudo lvextend -L +64M -r /dev/vglesson12/lvdata
sudo lvs -a -o +devices
df -h /mnt/lesson12-lvm
```

### 8.4 Full cleanup

```bash
lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-lvm-loop.sh
lessons/12-storage-filesystems-fstab-lvm/scripts/cleanup-storage-lab.sh
```

---

## 9. Cleanup

If you ran manual flow and leftovers remain:

```bash
sudo swapoff /tmp/lesson12-storage/swapfile 2>/dev/null || true
sudo umount /mnt/lesson12-data 2>/dev/null || true
LOOP_DEV="$(sudo losetup --list --noheadings --output NAME --associated /tmp/lesson12-storage/disk.img | head -n1)"
[[ -n "$LOOP_DEV" ]] && sudo losetup -d "$LOOP_DEV" || true
sudo sed -i '/lesson12-storage-lab/d' /etc/fstab
```

---

## 10. Lesson Summary

- **What I learned:** storage lifecycle (device -> filesystem -> mount), `fstab` behavior, safe `fsck` checks, and basic LVM layering.
- **What I practiced:** loop-backed ext4 lab, swapfile workflow, mount/swap validation, and safe cleanup.
- **What I can do manually now:** create a safe storage lab without touching real disks and troubleshoot typical mount/fstab issues.
- **Repo artifacts:** `lessons/12-storage-filesystems-fstab-lvm/scripts/`, `lessons/12-storage-filesystems-fstab-lvm/scripts/README.md`.