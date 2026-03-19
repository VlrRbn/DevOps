#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  enable-persistent-journal.sh

Examples:
  ./lessons/05-processes-systemd-services/scripts/enable-persistent-journal.sh
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

CONF_DIR="/etc/systemd/journald.conf.d"
CONF_FILE="$CONF_DIR/persistent.conf"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    exit 1
  }
}

need_cmd sudo
need_cmd systemctl
need_cmd journalctl

sudo mkdir -p /var/log/journal
sudo mkdir -p "$CONF_DIR"

sudo tee "$CONF_FILE" >/dev/null <<'CFG'
[Journal]
Storage=persistent
SystemMaxUse=200M
RuntimeMaxUse=50M
SystemMaxFileSize=50M
MaxFileSec=1month
Compress=yes
Seal=yes
CFG

sudo systemctl restart systemd-journald

echo "[OK] persistent journald enabled via $CONF_FILE"
journalctl --disk-usage
