#!/usr/bin/env bash
# Description: Remove namespace NAT/DNAT lab rules and restore sysctl values.
# Usage: cleanup-netns-nat.sh [--state-file PATH]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  cleanup-netns-nat.sh [--state-file PATH]

Examples:
  ./lessons/10-networking-nat-dnat-netns-ufw/scripts/cleanup-netns-nat.sh
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

if [[ -f "$STATE_FILE" ]]; then
  # Prefer exact values from setup step for deterministic cleanup.
  # shellcheck disable=SC1090
  source "$STATE_FILE"
else
  # Fallback defaults when state file is missing.
  echo "[WARN] state file not found, using defaults" >&2
  NS="lab10"
  VETH_HOST="veth0"
  SUBNET="10.10.0.0/24"
  HOST_IP="10.10.0.1"
  NS_IP="10.10.0.2"
  PORT="8080"
  IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}')"
  PREV_IPF="0"
  PREV_RLN="0"
fi

set +e

# Stop namespace HTTP service if still running.
sudo ip netns exec "$NS" bash -lc "kill \"\$(cat /tmp/${NS}_http.pid 2>/dev/null)\" 2>/dev/null || true" 2>/dev/null || true

# Remove NAT/DNAT and FORWARD rules (ignore if already absent).
sudo iptables -t nat -D PREROUTING -p tcp --dport "$PORT" -j DNAT --to-destination "$NS_IP:$PORT" 2>/dev/null || true
sudo iptables -D FORWARD -p tcp -d "$NS_IP" --dport "$PORT" -j ACCEPT 2>/dev/null || true
sudo iptables -t nat -D OUTPUT -p tcp --dport "$PORT" -d 127.0.0.1 -j DNAT --to-destination "$NS_IP:$PORT" 2>/dev/null || true
sudo iptables -t nat -D POSTROUTING -o "$VETH_HOST" -p tcp -d "$NS_IP" --dport "$PORT" -j SNAT --to-source "$HOST_IP" 2>/dev/null || true

sudo iptables -D FORWARD -i "$VETH_HOST" -o "$IF" -s "$SUBNET" -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i "$IF" -o "$VETH_HOST" -d "$SUBNET" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
sudo iptables -t nat -D POSTROUTING -s "$SUBNET" -o "$IF" -j MASQUERADE 2>/dev/null || true

# Remove namespace and veth artifacts.
sudo ip netns del "$NS" 2>/dev/null || true
ip link show "$VETH_HOST" >/dev/null 2>&1 && sudo ip link del "$VETH_HOST" 2>/dev/null || true

# Restore sysctl to previous values captured by setup.
sudo sysctl -w net.ipv4.ip_forward="$PREV_IPF" >/dev/null 2>&1 || true
sudo sysctl -w "net.ipv4.conf.$VETH_HOST.route_localnet=$PREV_RLN" >/dev/null 2>&1 || true

# Remove state file to avoid stale future runs.
rm -f "$STATE_FILE"

echo "[OK] cleanup completed"
