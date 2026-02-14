# lesson_06

# Package Management with APT and DPKG

**Date:** 2025-08-26  
**Topic:** APT/dpkg workflow: search, policy, versions, file ownership, holds, snapshots, and unattended upgrades  
**Daily goal:** Learn to inspect package state, simulate changes safely, and prepare rollback-oriented package operations.
**Bridge:** [05-07 Operations Bridge](../00-foundations-bridge/05-07-operations-bridge.md) for missing practical gaps after lessons 5-7.

---

## 1. Core Concepts

### 1.1 APT vs DPKG vs APT-CACHE

- `dpkg` works with installed packages and local `.deb` files.
- `apt` / `apt-get` work with repositories and dependency resolution.
- `apt-cache` is a read-only metadata tool (stable output, script-friendly).

Practical split:

- **interactive:** `apt`
- **automation/scripts:** `apt-get` + `apt-cache`

### 1.2 Package state model

A package can be:

- installed
- upgradable
- on hold
- auto-installed dependency
- manually installed

Useful state checks:

- installed vs candidate version
- manual vs auto install reason
- hold list

### 1.3 Why simulation matters

Use simulation before real changes:

- `apt-get -s upgrade`
- `apt-get -s full-upgrade`
- `apt-get -s dselect-upgrade`

This prevents accidental removals and shows impact in advance.

### 1.4 Where package data lives

- Repository config: `/etc/apt/sources.list`, `/etc/apt/sources.list.d/*.list`
- Package status DB: `/var/lib/dpkg/status`
- APT cache: `/var/cache/apt/archives/`
- Unattended-upgrades config (cadence): `/etc/apt/apt.conf.d/20auto-upgrades`
- Unattended-upgrades config (rules): `/etc/apt/apt.conf.d/50unattended-upgrades`

### 1.5 How APT chooses a version (Candidate)

APT version selection is mostly:

1. compare source priority (Pin-Priority)
2. if priorities are equal, pick the newer version

`Candidate` is the version APT would install right now with `apt install <pkg>` or `apt upgrade`.

If `Installed` differs from `Candidate`, an update is available (or a different source priority is winning).

### 1.6 Mini glossary for this lesson

- `Installed`: version already installed on the host.
- `Candidate`: version APT would choose for install/upgrade now.
- `Version table`: available versions from sources with priorities.
- `Pin-Priority`: numeric version-selection rule (e.g., `500`, `990`).
- `hold`: prevents automatic upgrade of the package.
- `full-upgrade`: upgrade mode that may add/remove packages to resolve dependencies.
- `autoremove`: removes auto-installed dependencies no longer needed.
- `phased update`: gradual rollout of an update to a subset of machines.

### 1.7 Operational workflow: `read -> simulate -> apply`

Safe package-change sequence:

1. `read`: collect context (`apt show`, `apt-cache policy`, `apt list --upgradable`).
2. `simulate`: preview impact without changes (`apt-get -s upgrade` / `-s full-upgrade`).
3. `apply`: run real command only after review.
4. `verify`: validate outcome (`apt list --upgradable`, service health, logs).

Practical rule:

- if you skip simulation, you are making a higher-risk change.

---

## 2. Command Priority (What to Learn First)

### Core (must know now)

- `apt update`
- `apt list --upgradable`
- `apt show <pkg>`
- `apt-cache policy <pkg>`
- `dpkg -L <pkg>`
- `dpkg -S <file>`
- `apt-mark hold|unhold|showhold`
- `apt-get -s upgrade`

### Optional (useful after core)

- `apt search <pkg>`
- `apt list -a <pkg>`
- `apt-cache madison <pkg>`
- `apt-cache depends <pkg>` / `apt-cache rdepends <pkg>`
- `apt-mark showmanual` / `apt-mark showauto`
- `apt-file search <path>`

### Advanced (for safer operations)

- package snapshot/restore using `dpkg --get-selections` and `dpkg --set-selections`
- `apt-get -s dselect-upgrade` before any restore
- phased updates behavior and override flag
- unattended-upgrades dry-run and log validation
- cache hygiene (`apt-get autoclean`, careful use of `autoremove`)

---

## 3. Core Commands: What / Why / When

### `apt update`

- **What:** refreshes package index from configured repositories.
- **Why:** without fresh index, policy/search results may be stale.
- **When:** before any package audit or change.

```bash
sudo apt update
```

### `apt list --upgradable`

- **What:** shows installed packages with available newer versions.
- **Why:** quick update backlog view.
- **When:** daily/weekly patch planning.

```bash
apt list --upgradable 2>/dev/null | head -n 20
```

### `apt show <pkg>`

- **What:** package metadata (depends, maintainer, description).
- **Why:** understand what you are about to install/update.
- **When:** before install/upgrade decisions.

```bash
apt show htop | sed -n '1,25p'
```

### `apt-cache policy <pkg>`

- **What:** installed version, candidate version, origin priorities.
- **Why:** explains why a version is selected.
- **When:** troubleshooting version mismatch.

```bash
apt-cache policy htop
```

How to read the output:

```text
htop:
  Installed: 3.3.0-4build1
  Candidate: 3.3.0-4build1
  Version table:
 *** 3.3.0-4build1 500
        500 http://archive.ubuntu.com/ubuntu noble/main amd64 Packages
        100 /var/lib/dpkg/status
```

- `Installed`: currently installed version.
- `Candidate`: version APT would choose for install/upgrade now.
- `Version table`: available versions and their priorities.
- `***`: marks the currently installed version.

What `500` means:

- It is Pin-Priority for that source/repository.
- `500` usually means a normal enabled repository.
- It is not a percentage or quality score; it is a selection rule weight.

Quick priority guide:

- `100`: usually the installed version from local dpkg status.
- `500`: normal repository priority.
- `990`: target release priority (when `APT::Default-Release` is set).
- `1001+`: force-preferred versions (often via pinning).
- `<0`: version is blocked from installation.

Where pinning rules live:

- `/etc/apt/preferences`
- `/etc/apt/preferences.d/*.pref`

### `dpkg -L <pkg>`

- **What:** files installed by a package.
- **Why:** locate binaries/config/docs.
- **When:** “where did this package place files?”.

```bash
dpkg -L htop | head -n 20
```

### `dpkg -S <file>`

- **What:** find installed package owning a file.
- **Why:** map binary/library to package name.
- **When:** incident/debugging from filesystem path.

```bash
dpkg -S /usr/bin/journalctl
```

### `apt-mark hold|unhold|showhold`

- **What:** freeze/unfreeze package upgrades.
- **Why:** protect known-good version during incident windows.
- **When:** temporary risk control.

```bash
sudo apt-mark hold htop
apt-mark showhold | grep -E '^htop$' || true
sudo apt-mark unhold htop
```

Important hold caveats:

- `hold` protects from routine `upgrade/full-upgrade`, but it is not a full change-management strategy.
- `hold` is easy to forget; package can stay outdated and miss important fixes.
- review `apt-mark showhold` regularly and track why each hold exists.

### `apt-get -s upgrade`

- **What:** simulated safe upgrade (no package removal).
- **Why:** preview exact change set.
- **When:** pre-change validation.

```bash
sudo apt-get -s upgrade | sed -n '1,40p'
```

---

## 4. Optional Commands (After Core)

### `apt search <pkg>` / `apt list -a <pkg>` / `apt-cache madison <pkg>`

- **What:** `apt search` finds packages by name/description; `apt list -a` shows all available versions; `apt-cache madison` shows a compact “version -> source” matrix.
- **Why:** quickly compare version availability and source origin.
- **When:** selecting versions, validating repo visibility, preparing pinning.

```bash
apt search htop | sed -n '1,20p'
apt list -a nginx 2>/dev/null | head -n 10
apt-cache madison nginx
```

### `apt-cache depends <pkg>` / `apt-cache rdepends <pkg>`

- **What:** `depends` shows what the package requires; `rdepends` shows what depends on that package.
- **Why:** estimate blast radius before removal/change.
- **When:** before `remove/purge` or risky package substitutions.

```bash
apt-cache depends htop | sed -n '1,30p'
apt-cache rdepends htop | sed -n '1,30p'
```

### `apt-mark showmanual` / `apt-mark showauto`

- **What:** shows manual vs dependency-installed packages.
- **Why:** predict what `autoremove` may remove.
- **When:** cleanup, image minimization, migration prep.

```bash
apt-mark showmanual | head -n 20
apt-mark showauto | head -n 20
```

Practical rule:

- before `autoremove`, inspect `showauto` to avoid deleting needed runtime components.

### `apt-file search <path>`

- **What:** find package by file path even if the package is not installed.
- **Why:** solves cases where `dpkg -S` cannot help.
- **When:** “which package contains this binary/lib?” investigations.

```bash
sudo apt install -y apt-file
sudo apt-file update
apt-file search bin/journalctl | head -n 10
```

---

## 5. Advanced Topics (Snapshots, Restore, Unattended)

Advanced here means operations that affect system integrity at scale:

- mass package-state changes
- automated unattended patching
- rollout behavior overrides (phasing)

### 5.1 Snapshot current package selections

- **What:** capture package state into files.
- **Why:** create rollback anchor before risky changes.
- **When:** before major upgrades, migrations, broad maintenance.

```bash
lessons/06-apt-dpkg-package-management/scripts/pkg-snapshot.sh ./pkg-state
```

Outputs:

- `packages.list` (machine-readable selections)
- `packages_table.txt` (human-readable table)

### 5.2 Restore safely (simulate first)

- **What:** restore package-state from `packages.list`.
- **Why:** return to known-good selection state.
- **When:** failed upgrade, drift cleanup, host rebuild.

Simulation (default):

```bash
lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh ./pkg-state/packages.list
```

Real apply:

```bash
lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh --apply ./pkg-state/packages.list
```

### 5.3 Inspect `.deb` without installing

- **What:** inspect package metadata/contents offline.
- **Why:** validate dependencies and file layout before install.
- **When:** security review, external repo trust checks, pre-approval analysis.

```bash
apt-get download htop
dpkg -I htop_*.deb | sed -n '1,20p'
dpkg -c htop_*.deb | sed -n '1,20p'
rm -f htop_*.deb
```

### 5.4 Phased updates

- **What:** gradual rollout of updates across hosts.
- **Why:** reduce systemic risk from bad updates.
- **When:** keep default behavior in most production environments; override rarely and intentionally.

Check package phasing metadata:

```bash
apt-cache show <pkg> | grep -i Phased-Update-Percentage || true
```

Force include phased updates (high-risk):

```bash
sudo apt-get -o APT::Get::Always-Include-Phased-Updates=true upgrade -y
```

### 5.5 Unattended-upgrades validation

`unattended-upgrades` exists to apply updates (typically security) automatically, without waiting for manual runs.

Why this matters:

- faster vulnerability remediation
- fewer missed security patch windows
- more consistent baseline across servers

When it fits:

- hosts that need regular security patching even with limited manual ops time.

When to be careful:

- strict change-window production stacks where every update must pass staged approval.

Dry-run check via script:

```bash
lessons/06-apt-dpkg-package-management/scripts/unattended-dry-run.sh
```

The script checks:

- apt timers (`apt-daily*`)
- dry-run debug output
- latest unit logs
- `/var/log/unattended-upgrades/` presence

### 5.6 Cache hygiene

- **What:** `autoclean` removes obsolete cached `.deb` files.
- **Why:** saves disk space with low risk.
- **When:** periodic maintenance and post-upgrade cleanup.

```bash
sudo apt-get autoclean
```

### 5.7 Quick script run for this lesson

Scripts are in:

- `lessons/06-apt-dpkg-package-management/scripts/`

Help check:

```bash
./lessons/06-apt-dpkg-package-management/scripts/apt-dry-upgrade.sh --help
./lessons/06-apt-dpkg-package-management/scripts/pkg-snapshot.sh --help
./lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh --help
./lessons/06-apt-dpkg-package-management/scripts/unattended-dry-run.sh --help
```

Typical run sequence:

```bash
./lessons/06-apt-dpkg-package-management/scripts/pkg-snapshot.sh ./pkg-state
./lessons/06-apt-dpkg-package-management/scripts/apt-dry-upgrade.sh --full
./lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh ./pkg-state/packages.list
```

---

## 6. Mini-lab (Core Path)

### Goal

Inspect package state and simulate upgrades safely.

### Steps

1. Refresh repository metadata.
2. Review upgradable packages.
3. Inspect package metadata and version policy.
4. Verify file ownership mapping.
5. Simulate upgrade.

```bash
sudo apt update
apt list --upgradable 2>/dev/null | head -n 20

apt show htop | sed -n '1,20p'
apt-cache policy htop

dpkg -L htop | head -n 20
dpkg -S /usr/bin/journalctl

sudo apt-get -s upgrade | sed -n '1,40p'
```

Validation checklist:

- can explain installed vs candidate version
- can locate package files and owner package
- can preview upgrade impact before real change

---

## 7. Extended Lab (Optional + Advanced)

### 7.1 Snapshot and dry restore

```bash
lessons/06-apt-dpkg-package-management/scripts/pkg-snapshot.sh ./pkg-state
lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh ./pkg-state/packages.list
```

### 7.2 Compare version tools

```bash
apt list -a nginx 2>/dev/null | head -n 10
apt-cache madison nginx
apt-cache policy nginx
```

Goal: understand when to use each output type.

### 7.3 Dependency view

```bash
apt-cache depends htop | sed -n '1,30p'
apt-cache rdepends htop | sed -n '1,30p'
```

### 7.4 Unattended-upgrades dry validation

```bash
lessons/06-apt-dpkg-package-management/scripts/unattended-dry-run.sh
```

### 7.5 Hold/unhold practice

```bash
sudo apt-mark hold htop
apt-mark showhold | grep -E '^htop$' || true
sudo apt-mark unhold htop
```

---

## 8. Cleanup

```bash
rm -f htop_*.deb
```

If you created snapshot artifacts for lab only:

```bash
rm -rf ./pkg-state
```

---

## 9. Lesson Summary

- **What I learned:** package-state model, version selection logic, and safe simulation-first workflow.
- **What I practiced:** `apt/apt-cache/dpkg` triad, hold/unhold lifecycle, and ownership mapping.
- **Advanced skills:** package snapshot/restore workflow, phased updates awareness, unattended-upgrades dry validation.
- **Safety focus:** simulate before apply; avoid blind upgrades/removals.
- **Repo artifacts:** scripts in `lessons/06-apt-dpkg-package-management/scripts/`.
