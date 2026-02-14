#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  setup-flaky-service.sh [wait_seconds]

Examples:
  ./lessons/05-processes-systemd-services/scripts/setup-flaky-service.sh
  ./lessons/05-processes-systemd-services/scripts/setup-flaky-service.sh 10
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAIT_SECONDS="${1:-7}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! [[ "$WAIT_SECONDS" =~ ^[0-9]+$ ]]; then
  usage >&2
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
