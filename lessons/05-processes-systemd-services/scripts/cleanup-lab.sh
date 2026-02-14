#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  cleanup-lab.sh [--remove-cron-override]

Examples:
  ./lessons/05-processes-systemd-services/scripts/cleanup-lab.sh
  ./lessons/05-processes-systemd-services/scripts/cleanup-lab.sh --remove-cron-override
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REMOVE_CRON_OVERRIDE=0
if [[ "${1:-}" == "--remove-cron-override" ]]; then
  REMOVE_CRON_OVERRIDE=1
elif [[ -n "${1:-}" ]]; then
  usage
  exit 2
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    exit 1
  }
}

need_cmd sudo
need_cmd systemctl

sudo systemctl disable --now hello.timer 2>/dev/null || true
sudo systemctl stop hello.service flaky.service now-echo.service now-echo 2>/dev/null || true
sudo rm -f /etc/systemd/system/hello.service
sudo rm -f /etc/systemd/system/hello.timer
sudo rm -f /etc/systemd/system/flaky.service
sudo rm -f /usr/local/bin/hello.sh
sudo rm -f /etc/systemd/journald.conf.d/persistent.conf

if [[ "$REMOVE_CRON_OVERRIDE" -eq 1 ]]; then
  sudo rm -rf /etc/systemd/system/cron.service.d
fi

sudo systemctl daemon-reload
sudo systemctl reset-failed || true

echo "[OK] lesson 05 lab artifacts removed"
if [[ "$REMOVE_CRON_OVERRIDE" -eq 1 ]]; then
  echo "[OK] cron drop-in override removed"
fi
