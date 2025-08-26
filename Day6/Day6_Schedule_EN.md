# Day6_Schedule_EN

# Day 6 — Package Management (APT & dpkg)

**Date:** 26.08.2025

**Start:** **:** 11:00

**Total duration:** ~6h

**Format:** theory → practice → mini-labs (snapshot/restore) → unattended-upgrades → docs

---

## Warm-up (APT landscape)

- Show active repos (top 10 lines):
    
    ```bash
    grep -h ^deb /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null | sed 's/#.*//' | tr -s ' ' | head -10
    ```
    
- Update indices:
    
    ```bash
    sudo apt update
    apt list --upgradable 2>/dev/null | head -20
    ```
    

---

## Search / Info / Policy

- Find & inspect (use apt as default):
    
    ```bash
    apt search htop | head -10apt show htop | sed -n '1,25p'apt policy htop
    ```
    
- See all versions (two styles):
    
    ```bash
    apt list -a nginx 2>/dev/null | head -5apt-cache madison nginx
    ```
    

---

## Files, owners, and “which package has this file?”

- What files a package installs:
    
    ```bash
    sudo apt install -y htop
    dpkg -L htop | head -15
    ```
    
- Which package contains a file:
    
    ```bash
    sudo apt install -y apt-file && sudo apt-file update
    apt-file search bin/journalctl | head -5
    ```
    
- Who owns an installed path:
    
    ```bash
    dpkg -S /usr/bin/htop
    ```
    

---

## Holds & simulation

- Freeze/unfreeze a version:
    
    ```bash
    apt-mark hold htop
    apt-mark showhold | grep htop || trueapt-mark unhold htop
    ```
    
- Safe dry-run:
    
    ```bash
    sudo apt-get -s upgrade | sed -n '1,40p'
    ```
    
    > Note: if updates are phased, you may see “deferred due to phasing”. You can force it with:
    > 
    > 
    > `sudo apt-get -o APT::Get::Always-Include-Phased-Updates=true upgrade`
    > 
    > but it’s not the safest choice on prod; for learning, better wait.
    > 

---

## Mini-lab: package snapshot

- Script `tools/pkg-snapshot.sh`:
    
    ```bash
    mkdir -p tools
    cat > tools/pkg-snapshot.sh <<'SH'
    #!/usr/bin/env bash
    set -edpkg --get-selections > packages.list
    dpkg -l > packages_table.txt
    echo "Saved: packages.list (restore source) and packages_table.txt (readable table)."
    SH
    chmod +x tools/pkg-snapshot.sh
    ./tools/pkg-snapshot.sh
    ls -lh packages.list packages_table.txt
    ```
    

---

## Mini-lab: package restore (dry)

- Script `tools/pkg-restore.sh` (dry plan via `s` first):
    
    ```bash
    cat > tools/pkg-restore.sh <<'SH'
    #!/usr/bin/env bash
    set -e
    [ -f packages.list ] || { echo "packages.list not found"; exit 1; }
    sudo apt update
    sudo dpkg --set-selections < packages.list
    sudo apt-get -y dselect-upgrade
    SH
    chmod +x tools/pkg-restore.sh
    # dry plan (no changes)
    sudo dpkg --set-selections < packages.list
    sudo apt-get -s dselect-upgrade | sed -n '1,40p'
    ```
    

---

## Unattended-Upgrades (auto updates)

- Enable & basic cadence:
    
    ```bash
    sudo apt install -y unattended-upgrades
    sudo dpkg-reconfigure --priority=low unattended-upgrades   # Enable: Yes
    sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'CFG'
    APT::Periodic::Update-Package-Lists "1";
    APT::Periodic::Unattended-Upgrade "1";
    CFG
    ```
    
- Check timers & dry-run:
    
    ```bash
    systemctl list-timers --all | grep apt || systemctl list-timers --all | head -15
    sudo unattended-upgrade --dry-run --debug | sed -n '1,80p'
    # logs:
    journalctl -u apt-daily-upgrade.service -n 50 --no-pager
    ```
    
    > Config ordering note: filenames like 20auto-upgrades, 50unattended-upgrades — numbers indicate load order”.
    > 

---

## Cache hygiene (optional)

```bash
sudo apt-get autoclean
sudo apt-get clean
```

---

## Docs & artifacts (no push if you don’t want)

- Update `Day6_Materials_EN.md` (add Summary + Cheat sheet).
- Add `tools/pkg-snapshot.sh`, `tools/pkg-restore.sh` (+ optional `tools/apt-dry-upgrade.sh`):
    
    ```bash
    cat > tools/apt-dry-upgrade.sh <<'SH'
    #!/usr/bin/env bash
    set -e
    sudo apt update
    sudo apt-get -s upgrade
    SH
    chmod +x tools/apt-dry-upgrade.sh
    ```
    

---

## Cheat sheet

- Find: `apt search <pkg>` ⟷ `apt-cache search <pkg>`
- Info: `apt show <pkg>` ⟷ `apt-cache show <pkg>`
- Versions: `apt list -a <pkg>` ⟷ `apt-cache madison <pkg>`
- Policy: `apt policy <pkg>` ⟷ `apt-cache policy <pkg>`
- Download: `apt download <pkg>` ⟷ `apt-get download <pkg>`
- Deps: *(not in apt)* ⟷ `apt-cache depends|rdepends <pkg>`
- Simulate: `apt -s upgrade` ⟷ `apt-get -s upgrade`