#!/usr/bin/env bash
# Description: Validate nftables netns lab and print counters/troubleshooting context.
# Usage: check-nft-netns.sh [--state-file PATH] [--trace-once]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  check-nft-netns.sh [--state-file PATH] [--trace-once]

Examples:
  ./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh
  ./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh --trace-once
USAGE
}

STATE_FILE="/tmp/lesson11_nft_state.env"
TRACE_ONCE=0
TRACE_TAG=""
TRACE_HANDLE=""

for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    usage
    exit 0
  fi
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file) STATE_FILE="${2:-}"; shift 2 ;;
    --trace-once) TRACE_ONCE=1; shift ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -f "$STATE_FILE" ]] || { echo "ERROR: state file not found: $STATE_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$STATE_FILE"

cleanup_trace_rule() {
  if [[ -n "$TRACE_HANDLE" ]]; then
    sudo nft delete rule ip nat output handle "$TRACE_HANDLE" 2>/dev/null || true
  elif [[ -n "$TRACE_TAG" ]]; then
    local handle
    handle="$(sudo nft -a list chain ip nat output 2>/dev/null | awk -v tag="$TRACE_TAG" '$0 ~ tag {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1); exit}}')"
    if [[ -n "$handle" ]]; then
      sudo nft delete rule ip nat output handle "$handle" 2>/dev/null || true
    fi
  fi
}

trap cleanup_trace_rule EXIT

echo "[INFO] NS=$NS IF=$IF PORT=$PORT HOST_EXT_IP=${HOST_EXT_IP:-N/A}"

# 1) L3 in lab subnet.
echo "[CHECK] namespace -> gateway"
sudo ip netns exec "$NS" ping -c 1 "$HOST_VETH_IP"

# 2) Outbound connectivity via nft masquerade.
echo "[CHECK] namespace -> internet"
sudo ip netns exec "$NS" ping -c 1 1.1.1.1

# 3) Localhost DNAT path.
echo "[CHECK] localhost DNAT"
if (( TRACE_ONCE )); then
  TRACE_TAG="lesson11-trace-once-$$-$RANDOM"
  echo "[TRACE] inserting temporary nftrace rule in ip nat/output (tag=$TRACE_TAG)"
  sudo nft insert rule ip nat output ip daddr 127.0.0.1 tcp dport "$PORT" meta nftrace set 1 comment "$TRACE_TAG"
  TRACE_HANDLE="$(sudo nft -a list chain ip nat output | awk -v tag="$TRACE_TAG" '$0 ~ tag {for(i=1;i<=NF;i++) if($i=="handle"){print $(i+1); exit}}')"
  if [[ -n "$TRACE_HANDLE" ]]; then
    echo "[TRACE] temporary rule handle: $TRACE_HANDLE"
  fi
  echo "[TRACE] if you want live trace output, start 'sudo nft monitor trace' in another terminal now"
fi
curl -sS --max-time 3 -I "http://127.0.0.1:$PORT" | sed -n '1,5p'

if (( TRACE_ONCE )); then
  cleanup_trace_rule
  TRACE_HANDLE=""
  TRACE_TAG=""
  echo "[TRACE] temporary nftrace rule removed"
fi

# 4) Optional external-IP hairpin path.
if [[ -n "${HOST_EXT_IP:-}" ]]; then
  echo "[CHECK] host external IP hairpin DNAT"
  curl -sS --max-time 3 -I "http://$HOST_EXT_IP:$PORT" | sed -n '1,5p' || true
fi

# 5) Show active nat table with counters.
echo "[CHECK] nft table ip nat"
sudo nft list table ip nat

echo "[OK] checks completed"
