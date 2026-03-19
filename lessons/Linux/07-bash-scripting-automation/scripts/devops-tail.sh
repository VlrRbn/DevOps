#!/usr/bin/env bash
# Description: Show systemctl status and recent journal lines for a systemd unit.
# Usage: devops-tail.sh <unit> [--since '1 hour ago']
# Output: First 12 lines of systemctl status and last 50 journal lines.
set -Eeuo pipefail
IFS=$'\n\t'

usage() {
  cat <<'USAGE'
Usage:
  devops-tail.sh <unit> [--since '1 hour ago']

Examples:
  ./lessons/07-bash-scripting-automation/scripts/devops-tail.sh cron
  ./lessons/07-bash-scripting-automation/scripts/devops-tail.sh ssh --since "30 min ago"
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ $# -ge 1 ]] || { usage; exit 1; }

unit="$1"
shift || true
since="10 min ago"
[[ "${1:-}" == "--since" ]] && since="${2:-$since}"

echo "== systemctl status $unit =="
systemctl status "$unit" --no-pager | sed -n '1,12p'

echo "== journalctl -u $unit --since '$since' =="
journalctl -u "$unit" --since "$since" -n 50 --no-pager
