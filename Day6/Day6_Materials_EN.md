# Day6_Materials_EN

# Package management (apt/dpkg)

**Date: 26.08.2025**

**Topic:** APT & dpkg essentials (search, policy, versions, files, holds).

**Daily goal:** Be able to audit, snapshot and safely simulate upgrades.

---

### Step 1 — “What’s in our repository lists?”.

`grep -h ^deb` — Check active sources and update the cache.

```bash
leprecha@Ubuntu-DevOps:~$ grep -h ^deb /etc/apt/sources.list /etc/apt/sources.list.d/*list 2>/dev/null | tr -s ' ' | head -10
deb [arch=amd64] https://dl.google.com/linux/chrome/deb/ stable main
```

- `grep -h ^deb` — extracts active repositories (`deb` lines).
- `2>/dev/null` — hides errors if some file doesn’t exist.
- `tr -s ' '` — normalizes spaces, alternative - `sed -E 's/[[:space:]]+/ /g'`.
- `head -10` — shows the first 10 only.

---

`sudo apt update` — Updates the package index from those repositories (doesn’t install anything yet).

```bash
leprecha@Ubuntu-DevOps:~$ sudo apt update
Fetched 5,283 kB in 1s (3,570 kB/s)                               
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
13 packages can be upgraded. Run 'apt list --upgradable' to see them.
```

---

### Step 2 — What can be updated (without actually upgrading).

`apt list --upgradable` — show list of upgradable packages.

- Lists packages that have newer versions available in the repositories.
- Output includes package name, available version, repo, and currently installed version.

```bash
leprecha@Ubuntu-DevOps:~$ apt list --upgradable 2>/dev/null | head -20
Listing...
bluez-cups/noble-updates 5.72-0ubuntu5.4 amd64 [upgradable from: 5.72-0ubuntu5.3]
bluez-obexd/noble-updates 5.72-0ubuntu5.4 amd64 [upgradable from: 5.72-0ubuntu5.3]
bluez/noble-updates 5.72-0ubuntu5.4 amd64 [upgradable from: 5.72-0ubuntu5.3]
code/stable 1.103.2-1755709794 amd64 [upgradable from: 1.103.1-1755017277]
gir1.2-gtk-4.0/noble-updates 4.14.5+ds-0ubuntu0.5 amd64 [upgradable from: 4.14.5+ds-0ubuntu0.4]
libbluetooth3/noble-updates 5.72-0ubuntu5.4 amd64 [upgradable from: 5.72-0ubuntu5.3]
libgtk-4-1/noble-updates 4.14.5+ds-0ubuntu0.5 amd64 [upgradable from: 4.14.5+ds-0ubuntu0.4]
libgtk-4-bin/noble-updates 4.14.5+ds-0ubuntu0.5 amd64 [upgradable from: 4.14.5+ds-0ubuntu0.4]
libgtk-4-common/noble-updates,noble-updates 4.14.5+ds-0ubuntu0.5 all [upgradable from: 4.14.5+ds-0ubuntu0.4]
libgtk-4-media-gstreamer/noble-updates 4.14.5+ds-0ubuntu0.5 amd64 [upgradable from: 4.14.5+ds-0ubuntu0.4]
screen-resolution-extra/noble-updates,noble-updates 0.18.3ubuntu0.24.04.1 all [upgradable from: 0.18.3]
xserver-xorg-video-nouveau/noble-updates 1:1.0.17-2ubuntu0.1 amd64 [upgradable from: 1:1.0.17-2build1]
xserver-xorg-video-vesa/noble-updates 1:2.6.0-1ubuntu0.1 amd64 [upgradable from: 1:2.6.0-1]
```

Useful for a quick glance at pending updates.

---

`sudo apt-get -s upgrade` — safe "dry-run" upgrade simulation.

- Upgrades all packages with new versions available.
- **Does not remove** packages and **does not install** new dependencies.
- **`-s`** — simulation only: nothing is actually changed.

```bash
leprecha@Ubuntu-DevOps:~$ sudo apt-get -s upgrade | head -30
Reading package lists...
Building dependency tree...
Reading state information...
Calculating upgrade...
The following upgrades have been deferred due to phasing:
  gir1.2-gtk-4.0 libgtk-4-1 libgtk-4-bin libgtk-4-common
  libgtk-4-media-gstreamer xserver-xorg-video-nouveau xserver-xorg-video-vesa
The following packages will be upgraded:
  bluez bluez-cups bluez-obexd code libbluetooth3 screen-resolution-extra
6 upgraded, 0 newly installed, 0 to remove and 7 not upgraded.
Inst bluez [5.72-0ubuntu5.3] (5.72-0ubuntu5.4 Ubuntu:24.04/noble-updates [amd64])
Inst bluez-cups [5.72-0ubuntu5.3] (5.72-0ubuntu5.4 Ubuntu:24.04/noble-updates [amd64])
Inst bluez-obexd [5.72-0ubuntu5.3] (5.72-0ubuntu5.4 Ubuntu:24.04/noble-updates [amd64])
Inst code [1.103.1-1755017277] (1.103.2-1755709794 code stable:stable [amd64])
Inst libbluetooth3 [5.72-0ubuntu5.3] (5.72-0ubuntu5.4 Ubuntu:24.04/noble-updates [amd64])
Inst screen-resolution-extra [0.18.3] (0.18.3ubuntu0.24.04.1 Ubuntu:24.04/noble-updates [all])
Conf bluez (5.72-0ubuntu5.4 Ubuntu:24.04/noble-updates [amd64])
Conf bluez-cups (5.72-0ubuntu5.4 Ubuntu:24.04/noble-updates [amd64])
Conf bluez-obexd (5.72-0ubuntu5.4 Ubuntu:24.04/noble-updates [amd64])
Conf code (1.103.2-1755709794 code stable:stable [amd64])
Conf libbluetooth3 (5.72-0ubuntu5.4 Ubuntu:24.04/noble-updates [amd64])
Conf screen-resolution-extra (0.18.3ubuntu0.24.04.1 Ubuntu:24.04/noble-updates [all])
```

Lets you preview upgrades safely before doing the real thing.

---

### Step 3 — Search, info, and version policy (using htop as an example)

**1)** `apt search htop` — s**earch for a package by name/description**

```bash
leprecha@Ubuntu-DevOps:~$ apt search htop | head -10

WARNING: apt does not have a stable CLI interface. Use with caution in scripts.

Sorting...
Full Text Search...
aha/noble 0.5.1-3build1 amd64
  ANSI color to HTML converter

bashtop/noble,noble 0.9.25-1 all
  Resource monitor that shows usage and stats

bpytop/noble,noble 1.0.68-2 all
  Resource monitor that shows usage and stats
```

For exact name matches, a handy trick is:

```bash
leprecha@Ubuntu-DevOps:~$ apt search htop | grep htop
WARNING: apt does not have a stable CLI interface. Use with caution in scripts.
bashtop/noble,noble 0.9.25-1 all
htop/noble,now 3.3.0-4build1 amd64 [installed]

leprecha@Ubuntu-DevOps:~$ apt list --installed | grep -E '^htop/'
WARNING: apt does not have a stable CLI interface. Use with caution in scripts.
htop/noble,now 3.3.0-4build1 amd64 [installed]

leprecha@Ubuntu-DevOps:~$ apt list 2>/dev/null | grep -E '^htop/'
htop/noble,now 3.3.0-4build1 amd64 [installed]
```

---

### 2) Compact package “card” (metadata)

`apt show htop`

```bash
leprecha@Ubuntu-DevOps:~$ apt show htop | sed -n '1,25p'

WARNING: apt does not have a stable CLI interface. Use with caution in scripts.

Package: htop
Version: 3.3.0-4build1
Priority: optional
Section: utils
Origin: Ubuntu
Maintainer: Ubuntu Developers <ubuntu-devel-discuss@lists.ubuntu.com>
Original-Maintainer: Daniel Lange <DLange@debian.org>
Bugs: https://bugs.launchpad.net/ubuntu/+filebug
Installed-Size: 434 kB
Depends: libc6 (>= 2.38), libncursesw6 (>= 6), libnl-3-200 (>= 3.2.7), libnl-genl-3-200 (>= 3.2.7), libtinfo6 (>= 6)
Suggests: lm-sensors, lsof, strace
Homepage: https://htop.dev/
Task: cloud-image, cloud-image, server, ubuntu-server-raspi, lubuntu-desktop, ubuntu-mate-core, ubuntu-mate-desktop, ubuntu-budgie-desktop-minimal, ubuntu-budgie-desktop, ubuntu-budgie-desktop-raspi
Download-Size: 171 kB
APT-Manual-Installed: yes
APT-Sources: http://ie.archive.ubuntu.com/ubuntu noble/main amd64 Packages
Description: interactive processes viewer
 Htop is an ncursed-based process viewer similar to top, but it
 allows one to scroll the list vertically and horizontally to see
 all processes and their full command lines.
 .
 Tasks related to processes (killing, renicing) can be done without
 entering their PIDs.
```

- **What it does:** prints package metadata: `Version`, `Maintainer`, `Depends`, `Homepage`, `Description`, etc.
- **Why `sed`:** `apt show` can be long; `sed -n '1,25p'` shows the first 25 lines for a quick scan.

---

### 3) Versions and where they come from (pinning/priorities)

`apt-cache policy htop`

```bash
leprecha@Ubuntu-DevOps:~$ apt-cache policy htop
htop:
  Installed: 3.3.0-4build1
  Candidate: 3.3.0-4build1
  Version table:
 *** 3.3.0-4build1 500
        500 http://ie.archive.ubuntu.com/ubuntu noble/main amd64 Packages
        100 /var/lib/dpkg/status
```

- **What it does:** shows:
    - `Installed` — currently installed version.
    - `Candidate` — the version `apt install` would choose.
    - `Version table` — all available versions with their **origin** (repo/priorities).
- **In practice:**
    - If `Installed` ≠ `Candidate` → an update is available.
    - Low `Pin-Priority` explains why a repo’s version isn’t selected.
    - Great to debug “why this version”.

Fast workflow: `apt search NAME`→ locate the package → `apt show NAME` to review deps/description → `apt-cache policy NAME` to verify versions and source.

---

### Step 4 — Where the package files are located and which package provides a file

**1) Install the package**

```bash
leprecha@Ubuntu-DevOps:~$ sudo apt install -y htop
[sudo] password for leprecha: 
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
htop is already the newest version (3.3.0-4build1).
0 upgraded, 0 newly installed, 0 to remove and 13 not upgraded.
```

- **`sudo apt install`** — installs the package (plus its dependencies).
- **`y`** — auto-answers “yes” to prompts (great for scripts).
- If the package is already installed → “htop is already the newest version”.

---

**2) Show what files the package installs**

```bash
leprecha@Ubuntu-DevOps:~$ dpkg -L htop | head -15
/.
/usr
/usr/bin
/usr/bin/htop
/usr/share
/usr/share/applications
/usr/share/applications/htop.desktop
/usr/share/doc
/usr/share/doc/htop
/usr/share/doc/htop/AUTHORS
/usr/share/doc/htop/README.gz
/usr/share/doc/htop/changelog.Debian.gz
/usr/share/doc/htop/copyright
/usr/share/icons
/usr/share/icons/hicolor
```

- **`dpkg -L <pkg>`** (List files) — shows all files installed by that package.
- Useful to check:
    - where the binary lives (`/usr/bin/htop`),
    - where docs are (`/usr/share/doc/htop/`),
    - if there are configs (`/etc/...`).

---

**3) Find which package provides a file**

```bash
leprecha@Ubuntu-DevOps:~$ sudo apt install -y apt-file && sudo apt-file update

leprecha@Ubuntu-DevOps:~$ apt-file search bin/journalctl | head -5
systemd: /usr/bin/journalctl
```

- **`apt-file`** — a separate tool to search *package contents*, even for packages not installed yet.
- **`sudo apt-file update`** — refreshes its database (must run once after install).
- **`apt-file search <path>`** — finds which package provides the given file.
    - Example: `apt-file search bin/journalctl` will show that the `journalctl` binary belongs to the `systemd` package.

---

### Step 5 — Hold / Unhold (version freeze)

Using the safe example of htop

**1) Freeze a package (prevent upgrades)**

```bash
leprecha@Ubuntu-DevOps:~$ sudo apt-mark hold htop
htop set on hold.
```

- **`apt-mark hold <pkg>`** — marks the package as “on hold.”
- Meaning: `htop` will **not be upgraded**, even if a new version appears in the repos.
- Useful if:
    - you need to keep a specific version (stable for production),
    - the newer release breaks compatibility.

---

**2) Check which packages are on hold**

```bash
leprecha@Ubuntu-DevOps:~$ apt-mark showhold | grep htop || true
htop
```

- **`apt-mark showhold`** — lists all packages currently on hold.
- `grep htop` — filters only `htop`.
- `|| true` — ensures the command exits cleanly even if `grep` finds nothing (since `grep` returns exit code 1 when no matches).

---

**3) Unfreeze (allow upgrades again)**

```bash
leprecha@Ubuntu-DevOps:~$ sudo apt-mark unhold htop
Canceled hold on htop.
```

- **`apt-mark unhold <pkg>`** — removes the hold.
- After this, the package will be upgraded normally with `apt upgrade`.

---

### Step 6 — Snapshot of the package list (script)

Save the current “map” of packages.

**1) Create directory and script `pkg-snapshot.sh`, then make script executable.**

```bash
leprecha@Ubuntu-DevOps:~$ mkdir -p tools
leprecha@Ubuntu-DevOps:~$ cat > tools/pkg-snapshot.sh <<'SH'
> #!/usr/bin/env bash
> set -e
> dpkg --get-selections > packages.list
> dpkg -l > packages_table.txt
> echo "Saved: packages.list (for restore) and packages_table.txt (human-readable)."
> SH
leprecha@Ubuntu-DevOps:~$ chmod +x tools/pkg-snapshot.sh
```

- **`#!/usr/bin/env bash`** — run with bash.
- **`set -e`** — exit immediately if any command fails.
- **`dpkg --get-selections > packages.list`**
    - Saves package list + states (`install`, `hold`, `deinstall`, `purge`).
    - Machine-readable format for later restore with `dpkg --set-selections`.
- **`dpkg -l > packages_table.txt`**
    - Outputs a human-readable table (`ii`/`rc`, versions, names).
    - Great for humans, not for automated restore.
- **`echo ...`** — confirmation message.

---

**2) Run + check files**

```bash
leprecha@Ubuntu-DevOps:~$ ./tools/pkg-snapshot.sh
Saved: packages.list (for restore) and packages_table.txt (human-readable).
leprecha@Ubuntu-DevOps:~$ ls -lh packages.list packages_table.txt
-rw-r--r-- 1 leprecha sysadmin  60K Aug 26 11:53 packages.list
-rw-r--r-- 1 leprecha sysadmin 311K Aug 26 11:53 packages_table.txt
```

- Script runs, creates 2 files.
- `ls -lh` shows size & timestamp:
    - `packages.list` — compact (a few KB).
    - `packages_table.txt` — larger, because it includes descriptions.

---

Usage:

- To restore package selections later:
    
    ```bash
    sudo dpkg --set-selections < packages.list
    sudo apt-get dselect-upgrade
    ```
    
- Very useful before OS upgrades or server migrations.

---

If you need the **latest versions right now (not the safest)**.

```bash
sudo apt-get -o APT::Get::Always-Include-Phased-Updates=true upgrade -y
```

---

### Step 7 — Recovery script (pkg-restore) + “dry run”

Create `tools/pkg-restore.sh` and test without installing:

```bash
leprecha@Ubuntu-DevOps:~$ cat > tools/pkg-restore.sh <<'SH'
> #!/usr/bin/env bash
> set -e
> [ -f packages.list ] || { echo "packages.list not found"; exit 1; }
> sudo apt update
> sudo dpkg --set-selections < packages.list
> sudo apt-get -y dselect-upgrade
> SH
leprecha@Ubuntu-DevOps:~$ chmod +x tools/pkg-restore.sh
```

- Exits with a message if `packages.list` is missing.
- **`sudo apt update`**  — Refreshes package indexes.
- **`sudo dpkg --set-selections < packages.list`**
    
    Feeds the package list into `dpkg`, restoring the “desired states” (install/hold/remove/purge).
    
- **`sudo apt-get -y dselect-upgrade`**
    - Brings the system in sync with that selection list.
    - Installs or removes packages accordingly.

---

“Dry run” check (no changes)

```bash
leprecha@Ubuntu-DevOps:~$ sudo dpkg --set-selections < packages.list
[sudo] password for leprecha: 
leprecha@Ubuntu-DevOps:~$ sudo apt-get -s dselect-upgrade | sed -n '1,10p'
Reading package lists...
Building dependency tree...
Reading state information...
The following packages will be upgraded:
  bluez bluez-cups bluez-obexd code gir1.2-gtk-4.0 libbluetooth3 libgtk-4-1
  libgtk-4-bin libgtk-4-common libgtk-4-media-gstreamer
  screen-resolution-extra xserver-xorg-video-nouveau xserver-xorg-video-vesa
13 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
Inst bluez [5.72-0ubuntu5.3] (5.72-0ubuntu5.4 Ubuntu:24.04/noble-updates [amd64])
Inst bluez-cups [5.72-0ubuntu5.3] (5.72-0ubuntu5.4 Ubuntu:24.04/noble-updates [amd64])
```

- **`-s` (simulate)** → performs no actual changes.
- Shows what *would* be done (packages to install/remove).
- Perfect for testing before committing to a real restore.

---

Summary:

`pkg-snapshot.sh` = save the state.

`pkg-restore.sh` = restore the state.

Simulation (`-s`) = make sure you won’t break anything.

---

### Step 8 — Small APT hygiene `apt-get autoclean`

Save space in the cache without breaking anything:

```bash
leprecha@Ubuntu-DevOps:~$ sudo apt-get autoclean
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
```

- Removes **obsolete `.deb` packages** from cache (`/var/cache/apt/archives/`) — i.e. packages that are no longer downloadable from repos.
- A “smart cleanup”: free space but keeps current packages in case to reinstall.

---

# APT exploration

**A) Which versions are available from the repo (example: nginx)**

```bash
leprecha@Ubuntu-DevOps:~$ apt-cache madison nginx
     nginx | 1.24.0-2ubuntu7.5 | http://ie.archive.ubuntu.com/ubuntu noble-updates/main amd64 Packages
     nginx | 1.24.0-2ubuntu7.5 | http://security.ubuntu.com/ubuntu noble-security/main amd64 Packages
     nginx | 1.24.0-2ubuntu7 | http://ie.archive.ubuntu.com/ubuntu noble/main amd64 Packages
```

Lists **all available versions** of the package and their origin (repos).

- Useful to:
    - see all versions across repos,
    - install a specific one (`apt install nginx=1.24.0-2ubuntu7`).

---

```bash
leprecha@Ubuntu-DevOps:~$ apt-cache policy nginx
nginx:
  Installed: 1.24.0-2ubuntu7.5
  Candidate: 1.24.0-2ubuntu7.5
  Version table:
 *** 1.24.0-2ubuntu7.5 500
        500 http://ie.archive.ubuntu.com/ubuntu noble-updates/main amd64 Packages
        500 http://security.ubuntu.com/ubuntu noble-security/main amd64 Packages
        100 /var/lib/dpkg/status
     1.24.0-2ubuntu7 500
        500 http://ie.archive.ubuntu.com/ubuntu noble/main amd64 Packages
```

Shows **a detailed view of version selection**:

- `Installed` — currently installed version,
- `Candidate` — the version `apt` would install now,
- `Version table` — all available versions + their priorities (Pin-Priority) and repos.

---

Useful to:

- check why a certain version is chosen,
- see if updates exist,
- inspect repo priorities.

---

**B) Download a .deb without installing and look inside (using htop as an example)**

1) Download `.deb` without installing

```bash
leprecha@Ubuntu-DevOps:~$ apt-get download htop
Get:1 http://ie.archive.ubuntu.com/ubuntu noble/main amd64 htop amd64 3.3.0-4build1 [171 kB]
Fetched 171 kB in 0s (471 kB/s)
```

- Downloads the **.deb package file** into the current directory.
- Does **not install** it, just places the file, e.g.
- Clean — `rm -f htop_*.deb`.

---

2) Package metadata

```bash
leprecha@Ubuntu-DevOps:~$ dpkg -I htop_*.deb | sed -n '1,15p'
 new Debian package, version 2.0.
 size 170528 bytes: control archive=912 bytes.
     725 bytes,    18 lines      control
     582 bytes,     9 lines      md5sums
 Package: htop
 Version: 3.3.0-4build1
 Architecture: amd64
 Maintainer: Ubuntu Developers <ubuntu-devel-discuss@lists.ubuntu.com>
 Installed-Size: 424
 Depends: libc6 (>= 2.38), libncursesw6 (>= 6), libnl-3-200 (>= 3.2.7), libnl-genl-3-200 (>= 3.2.7), libtinfo6 (>= 6)
 Suggests: lm-sensors, lsof, strace
 Section: utils
 Priority: optional
 Homepage: https://htop.dev/
 Description: interactive processes viewer
```

**`dpkg -I <deb>`** (`--info`) → prints package info:

- name, version, architecture,
- dependencies (`Depends`),
- section, priority,
- description.

---

3) List files inside the package

```bash
leprecha@Ubuntu-DevOps:~$ dpkg -c htop_*.deb | head -20
drwxr-xr-x root/root         0 2024-04-08 16:59 ./
drwxr-xr-x root/root         0 2024-04-08 16:59 ./usr/
drwxr-xr-x root/root         0 2024-04-08 16:59 ./usr/bin/
-rwxr-xr-x root/root    379216 2024-04-08 16:59 ./usr/bin/htop
drwxr-xr-x root/root         0 2024-04-08 16:59 ./usr/share/
drwxr-xr-x root/root         0 2024-04-08 16:59 ./usr/share/applications/
-rw-r--r-- root/root      2546 2024-04-08 16:59 ./usr/share/applications/htop.desktop
drwxr-xr-x root/root         0 2024-04-08 16:59 ./usr/share/doc/
drwxr-xr-x root/root         0 2024-04-08 16:59 ./usr/share/doc/htop/
-rw-r--r-- root/root       226 2024-01-10 09:54 ./usr/share/doc/htop/AUTHORS
-rw-r--r-- root/root      2995 2024-01-10 09:54 ./usr/share/doc/htop/README.gz
-rw-r--r-- root/root      5337 2024-04-08 16:59 ./usr/share/doc/htop/changelog.Debian.gz
-rw-r--r-- root/root      1325 2024-01-10 11:41 ./usr/share/doc/htop/copyright
drwxr-xr-x root/root         0 2024-04-08 16:59 ./usr/share/icons/
drwxr-xr-x root/root         0 2024-04-08 16:59 ./usr/share/icons/hicolor/
drwxr-xr-x root/root         0 2024-04-08 16:59 ./usr/share/icons/hicolor/scalable/
drwxr-xr-x root/root         0 2024-04-08 16:59 ./usr/share/icons/hicolor/scalable/apps/
-rw-r--r-- root/root     11202 2024-04-08 16:59 ./usr/share/icons/hicolor/scalable/apps/htop.svg
drwxr-xr-x root/root         0 2024-04-08 16:59 ./usr/share/man/
drwxr-xr-x root/root         0 2024-04-08 16:59 ./usr/share/man/man1/
dpkg-deb: error: tar subprocess was killed by signal (Broken pipe)
```

- **`dpkg -c <deb> (--contents)`**   → shows all files inside the package and where they’ll be installed.
- Format: permissions, owner, size, path.
- `dpkg-deb: error: tar subprocess was killed by signal (Broken pipe)` → we can ignore it.
- Useful for inspection or manual install.

---

**C) Who owns a file (installed packages)**

```bash
leprecha@Ubuntu-DevOps:~$ dpkg -S /usr/bin/journalctl
systemd: /usr/bin/journalctl
leprecha@Ubuntu-DevOps:~$ dpkg -S /usr/bin/htop
htop: /usr/bin/htop
```

**`dpkg -S <file>`** (`--search`) → finds which installed package owns that file.

- Great when you discover a binary/lib and want to know its package.
- Works only for **installed packages**.

---

**D) What you installed manually vs automatically (good to know)**

1. Manual packages

```bash
leprecha@Ubuntu-DevOps:~$ apt-mark showmanual | head -10
acl
apt-file
bsdutils
btop
build-essential
code
curl
dash
diffutils
efibootmgr
```

- **`apt-mark showmanual`** — lists packages explicitly installed by you (`apt install`).
- They are considered important and **will not be auto-removed**.

---

```bash
leprecha@Ubuntu-DevOps:~$ apt-mark showauto | head -10
accountsservice
adduser
adwaita-icon-theme
alsa-base
alsa-topology-conf
alsa-ucm-conf
alsa-utils
amd64-microcode
anacron
apg
```

- **`apt-mark showauto`** — lists packages installed **automatically** as dependencies.
- These can be removed by `apt autoremove` if no longer needed.
- Promote a dependency to manual: `sudo apt-mark manual <pkg>`
- Demote a package back to auto: `sudo apt-mark auto <pkg>`

---

### Cheat sheet

- Find: `apt search <pkg>` ⟷ `apt-cache search <pkg>`
- Info: `apt show <pkg>` ⟷ `apt-cache show <pkg>`
- Versions: `apt list -a <pkg>` ⟷ `apt-cache madison <pkg>`
- Policy: `apt policy <pkg>` ⟷ `apt-cache policy <pkg>`
- Download .deb: `apt download <pkg>` ⟷ `apt-get download <pkg>`
- Deps: (not in apt) ⟷ `apt-cache depends|rdepends <pkg>`
- Simulate: `apt -s upgrade` ⟷ `apt-get -s upgrade`

---

**Dependencies and reverse dependencies (using `htop` as an example):**

`Depends` — what this package **needs**.

```bash
leprecha@Ubuntu-DevOps:~$ apt-cache depends htop | sed -n '1,20p'
htop
  Depends: libc6
  Depends: libncursesw6
  Depends: libnl-3-200
  Depends: libnl-genl-3-200
  Depends: libtinfo6
  Suggests: lm-sensors
  Suggests: lsof
  Suggests: strace
```

- **`apt-cache depends <pkg>`** — shows which packages the given one depends on.
- Relation types:
    - `Depends:` — mandatory dependencies.
    - `Recommends:` — optional but commonly needed.
    - `Suggests:` — purely optional extras.

---

`Rdepends` — who **needs this package**.

```bash
leprecha@Ubuntu-DevOps:~$ apt-cache rdepends htop | sed -n '1,20p'
htop
Reverse Depends:
  ubuntu-server
  far2l
  far2l
  ubuntu-server
  ubuntu-mate-desktop
  ubuntu-mate-core
  ubuntu-budgie-desktop-minimal
  ubuntu-budgie-desktop
  lubuntu-desktop
  hollywood
  freedombox
  far2l
```

- **`apt-cache rdepends <pkg>`** — shows which packages **depend on this package**.
- Who “pulls in” `htop`.

---

**Compare versions in two ways**

`apt list -a nginx`

```bash
leprecha@Ubuntu-DevOps:~$ apt list -a nginx 2>/dev/null | head -5
Listing...
nginx/noble-updates,noble-security,now 1.24.0-2ubuntu7.5 amd64 [installed]
nginx/noble 1.24.0-2ubuntu7 amd64
```

**`apt list -a <pkg>`** — lists all available versions of the package across repos.

- `a` → all versions.
- `2>/dev/null` → hides the “unstable CLI” warning.

Useful for seeing **which version is installed right now** (`[installed]`).

---

`apt policy nginx`

```bash
leprecha@Ubuntu-DevOps:~$ apt policy nginx
nginx:
  Installed: 1.24.0-2ubuntu7.5
  Candidate: 1.24.0-2ubuntu7.5
  Version table:
 *** 1.24.0-2ubuntu7.5 500
        500 http://ie.archive.ubuntu.com/ubuntu noble-updates/main amd64 Packages
        500 http://security.ubuntu.com/ubuntu noble-security/main amd64 Packages
        100 /var/lib/dpkg/status
     1.24.0-2ubuntu7 500
        500 http://ie.archive.ubuntu.com/ubuntu noble/main amd64 Packages
```

- **Installed** → version currently installed.
- **Candidate** → version `apt install` or `apt upgrade` will pick.
- **Version table** → all available versions:
    - `500` = pin-priority (normal repo).
    - `**` = currently installed version.
    - shows which repo (`updates`, `security`, `main`) provides it.
    
    ### Why it’s useful
    
    - See if updates are available (`Candidate` > `Installed`).
    - Know **which repo** the candidate comes from.
    - Debug why a specific version is chosen (via priorities).

---

`apt-cache madison`

```bash
leprecha@Ubuntu-DevOps:~$ apt-cache madison nginx
     nginx | 1.24.0-2ubuntu7.5 | http://ie.archive.ubuntu.com/ubuntu noble-updates/main amd64 Packages
     nginx | 1.24.0-2ubuntu7.5 | http://security.ubuntu.com/ubuntu noble-security/main amd64 Packages
     nginx | 1.24.0-2ubuntu7 | http://ie.archive.ubuntu.com/ubuntu noble/main amd64 Packages
```

Outputs all versions in a **compact “version → source” table**.

Shows:

- all available versions,
- repo/source for each,
- but **does not show** which version is installed.

Useful for quickly checking **what versions exist and where they come from**.

---

Summary:

- `apt list -a` → full list + shows installed version.
- `apt-cache madison` → compact version list + repo source (no installed info).

---

### Script `tools/apt-dry-upgrade.sh`

```bash
leprecha@Ubuntu-DevOps:~$ cat > tools/apt-dry-upgrade.sh <<'SH'
> #!/usr/bin/env bash
> set -e
> sudo apt update
> sudo apt-get -s upgrade
> SH
leprecha@Ubuntu-DevOps:~$ chmod +x tools/apt-dry-upgrade.sh
```

- **`#!/usr/bin/env bash`** — run with bash.
- **`set -e`** — exit immediately if any command fails.
- **`sudo apt update`** — refresh package indexes.
- **`sudo apt-get -s upgrade`** — simulate upgrade (`s = simulate`):
    - shows which packages *would* be upgraded,
    - but does **not actually install** anything.

Handy to run periodically, so you know exactly what would change before running a real `upgrade`.

---

## **Mini-summary**

### General difference between `apt vs apt-cache`

- **`apt`** — user-friendly: colored output, `[installed]`, `[upgradable]`, unified command set.
- **`apt-cache`** — older low-level tool, CLI output is stable, recommended for **scripting/automation**.
- `2>/dev/null` → hides the “unstable CLI” warning.

---

Key rule:

- For **interactive use** → `apt`.
- For **scripts** → `apt-get` + `apt-cache`.

---

### What is *phasing*

- **Phasing (phased updates)** = gradual rollout of updates.
- Each machine is randomly assigned a “phased percentage” → determines if you’re in the early wave.

---

### Why

- To **reduce the risk of mass breakage**.
- If an update is buggy → only a small group gets hit, Canonical can fix/rollback before it reaches everyone.
- It’s essentially a **canary release** mechanism at the OS package level.

---

### Can bypass it

Yes, you can force all phased updates immediately: but you’re among the first to get a possibly broken update.

```bash
sudo apt-get -o APT::Get::Always-Include-Phased-Updates=true upgrade -y
```

With this flag, you force `apt-get` to ignore phasing and install all available updates immediately.

---

 `dpkg -L`  and `apt-file search` difference:

- `dpkg -L` = “what files does this installed package provide?”
- `apt-file search` = “which package contains this file (even if I don’t have it)?”

---

## Unattended-Upgrades — mini guide + check

### What is `unattended-upgrades`

- A package/service that installs updates **automatically** without user intervention.
- Typically used for:
    - **security updates**,
    - optionally all package updates (if configured).
- Runs via `systemd` units (`apt-daily.service`, `apt-daily-upgrade.service`).

---

Config file: `/etc/apt/apt.conf.d/50unattended-upgrades`

Controls:

- which repos to auto-update (e.g. only `security`),
- auto-remove unused packages,
- auto-reboot if needed (`Unattended-Upgrade::Automatic-Reboot "true";`).

---

Global options:  `/etc/apt/apt.conf.d/20auto-upgrades` (numbers = order of config loading).

On servers: usually enable **security-only** updates → safer.

---

**Web interfaces for servers**

- **Webmin** → “Package Updates” module lets you configure auto-updates.
- **Cockpit** (with `software-updates` plugin) → manage updates from browser.

---

1. Update package indexes.
2. Install the package.
3. Configure via dialog.

```bash
leprecha@Ubuntu-DevOps:~$ sudo apt update
Hit:1 https://packages.microsoft.com/repos/code stable InRelease
Hit:2 http://ie.archive.ubuntu.com/ubuntu noble InRelease           
Hit:3 http://security.ubuntu.com/ubuntu noble-security InRelease    
Hit:4 http://ie.archive.ubuntu.com/ubuntu noble-updates InRelease   
Hit:5 https://dl.google.com/linux/chrome/deb stable InRelease
Hit:6 http://ie.archive.ubuntu.com/ubuntu noble-backports InRelease
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
7 packages can be upgraded. Run 'apt list --upgradable' to see them.
leprecha@Ubuntu-DevOps:~$ sudo apt install -y unattended-upgrades
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
unattended-upgrades is already the newest version (2.9.1+nmu4ubuntu1).
unattended-upgrades set to manually installed.
0 upgraded, 0 newly installed, 0 to remove and 7 not upgraded.
leprecha@Ubuntu-DevOps:~$ sudo dpkg-reconfigure --priority=low unattended-upgrades
```

- Installs the service that auto-applies updates.
- Creates:
    - config at `/etc/apt/apt.conf.d/50unattended-upgrades`
    - log at `/var/log/unattended-upgrades/unattended-upgrades.log`
    
    Brings up a dialog: **Enable automatic upgrades?**
    
    choose `Yes` → enables automatic security updates.
    

---

`systemctl list-timers`

```bash
leprecha@Ubuntu-DevOps:~$ systemctl list-timers | grep apt
Wed 2025-08-27 04:22:27 IST       8h Mon 2025-08-25 19:43:03 IST         - apt-daily.timer                apt-daily.service
Wed 2025-08-27 06:53:37 IST      11h Tue 2025-08-26 10:26:56 IST         - apt-daily-upgrade.timer        apt-daily-upgrade.service
```

Once enabled, daily systemd timers handle it.

---

**Unattended-Upgrades**

- unattended-upgrades: auto-updates via systemd timers (apt-daily, apt-daily-upgrade). Dry-run: `sudo unattended-upgrade --dry-run --debug`.
- Policy files: 20auto-upgrades (enable cadence), 50unattended-upgrades (origins/blacklist); logs via `journalctl -u apt-daily-upgrade`.

---

```bash
sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'CFG'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CFG
```

We can create a file to enable auto-start and daily checks — same as `dpkg-reconfigure unattended-upgrades`, but directly via the config.

---

`systemctl list-timers --all`

```bash
leprecha@Ubuntu-DevOps:~$ systemctl list-timers --all | grep apt || systemctl list-timers --all | head -10
Wed 2025-08-27 04:22:27 IST       8h Mon 2025-08-25 19:43:03 IST            - apt-daily.timer                apt-daily.service
Wed 2025-08-27 06:53:37 IST      11h Tue 2025-08-26 10:26:56 IST            - apt-daily-upgrade.timer        apt-daily-upgrade.service
```

- **`systemctl list-timers --all`**
    
    → shows all active timers in systemd.
    
- **`grep apt`**
    
    → filters for `apt` timers. Typically you’ll see:
    
    - `apt-daily.timer` → runs `apt update` daily.
    - `apt-daily-upgrade.timer` → runs `unattended-upgrades` daily.
- **`|| systemctl list-timers --all | head -10`**
    
    → if `grep` finds nothing (exit code 1), fall back to showing the first 10 timers (so you can still check if they’re missing/renamed).
    

---

`sudo unattended-upgrade --dry-run --debug | sed -n '1,10p'` — dry run

- **`sudo`** — requires root privileges.
- **`unattended-upgrade`** — tool from `unattended-upgrades` package.
- **`-dry-run`** — simulation only, nothing actually installed.
- **`-debug`** — verbose log:
    - which repos are checked,
    - which packages match the rules (`security`, `updates`),
    - which would be upgraded or skipped.
- **`| sed -n '1,10p'`** — print only the first 10 lines for readability.

`--dry-run --debug` = the best way to check the unattended-upgrades config before trusting it with the system.

---

### Where to check logs — Unattended-Upgrades.

`journalctl -u apt-daily-upgrade.service -n 50 --no-pager` - to check logs.

- **`journalctl`** — view systemd logs.
- **`u apt-daily-upgrade.service`** — filter logs for the `apt-daily-upgrade.service` unit (responsible for automatic upgrades).
- **`n 50`** — show last 50 lines.
- **`-no-pager`** — print directly to stdout (no `less`).

---

`sudo ls -l /var/log/unattended-upgrades/ 2>/dev/null || true`

```bash
leprecha@Ubuntu-DevOps:~$ sudo ls -l /var/log/unattended-upgrades/ 2>/dev/null || true
total 72
-rw-r--r-- 1 root adm   2101 Aug 23 16:13 unattended-upgrades-dpkg.log
-rw-r--r-- 1 root root 69004 Aug 26 19:40 unattended-upgrades.log
-rw-r--r-- 1 root root     0 Aug 19 15:19 unattended-upgrades-shutdown.log
```

---

## Daily Summary

**What learned:**

- Understood the difference between `apt`, `apt-get`, `apt-cache`.
- Learned how to find dependencies and reverse dependencies (`apt-cache depends/rdepends`).
- Mastered `dpkg -L`, `dpkg -S`, `apt-file search` → figured out where to see package files and how to find a package by file.
- Understood the mechanism of **phasing** (gradual updates) and **unattended-upgrades** (automatic updates).
- Performed dry-run updates (`apt-get -s`, `unattended-upgrade --dry-run`).

**What was hard:**

- Knowing exactly when to use `apt` vs `apt-cache` (for scripts or interactive use).
- Got a bit confused with timers (`apt-daily.timer`, `apt-daily-upgrade.timer`).
- A lot of information on `unattended-upgrades` — needs repetition.

**What to repeat:**

- Practice with `apt policy`, `apt list -a`.
- Run `dpkg -L`, `dpkg -S`, `apt-file search` on different packages.
- Test `unattended-upgrades` again (dry-run + systemctl timers).

**Artifacts created:**

- `tools/pkg-snapshot.sh` → makes a snapshot of installed packages.
- `tools/pkg-restore.sh` → restores the system from a snapshot.
- `tools/apt-dry-upgrade.sh` → upgrade simulation (dry-run).