#!/usr/bin/env bash
set -Eeuo pipefail; IFS=$'\n\t'
[[ $# -ge 1 ]] || { echo "Usage: $0 <unit> [--since '1 hour ago']"; exit 1; }
unit="$1"; shift || true
since="10 min ago"
[[ "${1:-}" == "--since" ]] && since="${2:-$since}"
echo "== systemctl status $unit =="; systemctl status "$unit" --no-pager | sed -n '1,12p'
echo "== journalctl -u $unit --since '$since' =="; journalctl -u "$unit" --since "$since" -n 50 --no-pager
