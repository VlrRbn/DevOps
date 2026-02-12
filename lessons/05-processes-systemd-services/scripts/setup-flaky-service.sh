#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAIT_SECONDS="${1:-7}"

if ! [[ "$WAIT_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 [wait_seconds]" >&2
  exit 2
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    exit 1
  }
}

need_cmd sudo
need_cmd install
need_cmd systemctl

sudo install -m 0644 "$SCRIPT_DIR/units/flaky.service" /etc/systemd/system/flaky.service
sudo systemctl daemon-reload
sudo systemctl restart flaky.service

sleep "$WAIT_SECONDS"

echo "[OK] flaky.service started; collecting quick status"
systemctl show -p NRestarts,ExecMainStatus flaky.service
journalctl -u flaky.service -n 20 --no-pager || true
