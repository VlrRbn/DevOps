#!/usr/bin/env bash
set -euo pipefail

REMOVE_CRON_OVERRIDE=0
if [[ "${1:-}" == "--remove-cron-override" ]]; then
  REMOVE_CRON_OVERRIDE=1
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
