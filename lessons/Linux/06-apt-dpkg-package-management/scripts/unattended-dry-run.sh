#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  unattended-dry-run.sh

Examples:
  ./lessons/06-apt-dpkg-package-management/scripts/unattended-dry-run.sh
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v unattended-upgrade >/dev/null 2>&1; then
  echo "ERROR: unattended-upgrade command not found" >&2
  echo "Install with: sudo apt install -y unattended-upgrades" >&2
  exit 1
fi

echo "[INFO] apt timers"
systemctl list-timers --all | grep -E 'apt-daily|apt-daily-upgrade' || true

echo
echo "[INFO] unattended-upgrade dry run (first 80 lines)"
sudo unattended-upgrade --dry-run --debug | sed -n '1,80p'

echo
echo "[INFO] latest apt-daily-upgrade.service logs"
journalctl -u apt-daily-upgrade.service -n 50 --no-pager || true

echo
echo "[INFO] log directory contents"
sudo ls -l /var/log/unattended-upgrades/ 2>/dev/null || true
