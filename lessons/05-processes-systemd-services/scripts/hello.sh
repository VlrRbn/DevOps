#!/usr/bin/env bash
# Emit a timestamped log line to journald with tag "hello".
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  hello.sh

Examples:
  ./lessons/05-processes-systemd-services/scripts/hello.sh
  journalctl -t hello -n 20 --no-pager
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

echo "[hello] $(date '+%F %T') $(hostname)" | systemd-cat -t hello -p info
