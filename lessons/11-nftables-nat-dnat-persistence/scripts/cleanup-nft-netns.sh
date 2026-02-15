#!/usr/bin/env bash
# Description: Cleanup nftables netns lab and restore previous sysctl values.
# Usage: cleanup-nft-netns.sh [--state-file PATH]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  cleanup-nft-netns.sh [--state-file PATH]

Examples:
  ./lessons/11-nftables-nat-dnat-persistence/scripts/cleanup-nft-netns.sh
USAGE
}

STATE_FILE="/tmp/lesson11_nft_state.env"

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
  # shellcheck disable=SC1090
  source "$STATE_FILE"
else
  echo "[WARN] state file not found, using defaults" >&2
  NS="lab11"
  SUBNET="10.10.0.0/24"
  VETH_HOST="veth0"
  IF="$(ip -o route show to default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}')"
  PREV_IPF="0"
  PREV_RLN="0"
  RULESET_FILE="/tmp/lesson11.nft"
fi

set +e

# Stop namespace HTTP service if still running.
sudo ip netns exec "$NS" bash -lc "kill \"\$(cat /tmp/${NS}_http.pid 2>/dev/null)\" 2>/dev/null || true" 2>/dev/null || true

# Remove only NAT table created by this lesson.
sudo nft delete table ip nat 2>/dev/null || true

# Remove namespace and veth artifacts.
sudo ip netns del "$NS" 2>/dev/null || true
if ip link show "$VETH_HOST" >/dev/null 2>&1; then
  sudo ip link del "$VETH_HOST" 2>/dev/null || true
fi

# Remove FORWARD allow rules created by setup script (if present).
if command -v iptables >/dev/null 2>&1; then
  while sudo iptables -C FORWARD -i "$VETH_HOST" -o "$IF" -s "$SUBNET" -j ACCEPT 2>/dev/null; do
    sudo iptables -D FORWARD -i "$VETH_HOST" -o "$IF" -s "$SUBNET" -j ACCEPT 2>/dev/null || true
  done
  while sudo iptables -C FORWARD -i "$IF" -o "$VETH_HOST" -d "$SUBNET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; do
    sudo iptables -D FORWARD -i "$IF" -o "$VETH_HOST" -d "$SUBNET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
  done
fi

# Restore previous sysctl values.
sudo sysctl -w net.ipv4.ip_forward="$PREV_IPF" >/dev/null 2>&1 || true
sudo sysctl -w "net.ipv4.conf.$VETH_HOST.route_localnet=$PREV_RLN" >/dev/null 2>&1 || true

rm -f "$STATE_FILE" "$RULESET_FILE"

echo "[OK] cleanup completed"
