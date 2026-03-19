#!/usr/bin/env bash
# Description: Validate namespace NAT/DNAT lab and print useful counters.
# Usage: check-netns-nat.sh [--state-file PATH]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  check-netns-nat.sh [--state-file PATH]

Examples:
  ./lessons/10-networking-nat-dnat-netns-ufw/scripts/check-netns-nat.sh
USAGE
}

STATE_FILE="/tmp/lesson10_netns_state.env"

# Parse CLI arguments.
for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    usage
    exit 0
  fi
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file) STATE_FILE="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -f "$STATE_FILE" ]] || { echo "ERROR: state file not found: $STATE_FILE" >&2; exit 1; }
# Load lab parameters produced by setup script.
# shellcheck disable=SC1090
source "$STATE_FILE"

echo "[INFO] NS=$NS IF=$IF PORT=$PORT"

# 1) Basic connectivity inside lab subnet.
echo "[CHECK] ping gateway from namespace"
sudo ip netns exec "$NS" ping -c 1 "$HOST_IP"

# 2) Outbound connectivity via NAT.
echo "[CHECK] internet reachability from namespace"
sudo ip netns exec "$NS" ping -c 1 1.1.1.1

# 3) Name resolution inside namespace.
echo "[CHECK] DNS from namespace"
sudo ip netns exec "$NS" getent hosts google.com | head -n 3 || true

# 4) Localhost DNAT/hairpin check.
echo "[CHECK] local DNAT (host 127.0.0.1:$PORT -> ns $NS_IP:$PORT)"
curl -sS --max-time 3 -I "http://127.0.0.1:$PORT" | sed -n '1,5p'

# 5) Rule hit counters to confirm real packet flow.
echo "[CHECK] nat counters (grep for MASQUERADE/SNAT/DNAT)"
sudo iptables -t nat -L -v -n --line-numbers | grep -E 'MASQUERADE|SNAT|DNAT' || true

echo "[CHECK] forward counters"
sudo iptables -L FORWARD -v -n --line-numbers | sed -n '1,40p'

echo "[OK] checks completed"
