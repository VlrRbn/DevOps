#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  setup-hello-timer.sh

Examples:
  ./lessons/05-processes-systemd-services/scripts/setup-hello-timer.sh
  systemctl list-timers --all | grep hello
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    exit 1
  }
}

need_cmd sudo
need_cmd install
need_cmd systemctl

sudo install -m 0755 "$SCRIPT_DIR/hello.sh" /usr/local/bin/hello.sh
sudo install -m 0644 "$SCRIPT_DIR/units/hello.service" /etc/systemd/system/hello.service
sudo install -m 0644 "$SCRIPT_DIR/units/hello.timer" /etc/systemd/system/hello.timer

sudo systemctl daemon-reload
sudo systemctl start hello.service
sudo systemctl enable --now hello.timer

echo "[OK] hello.service + hello.timer installed and started"
systemctl list-timers --all | grep -E "hello.timer|NEXT|LAST" || true
journalctl -u hello.service -n 20 --no-pager || true
journalctl -t hello -n 20 --no-pager || true
