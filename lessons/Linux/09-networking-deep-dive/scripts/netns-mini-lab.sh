#!/usr/bin/env bash
# Description: Create two namespaces, connect via veth, test ping + HTTP, then cleanup.
# Usage: netns-mini-lab.sh
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  netns-mini-lab.sh

Examples:
  ./lessons/09-networking-deep-dive/scripts/netns-mini-lab.sh
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# Cleanup function to ensure namespaces and processes are removed on exit
cleanup() {
  sudo ip netns exec red bash -lc 'kill "$(cat /tmp/netns_http.pid 2>/dev/null)" 2>/dev/null || true' 2>/dev/null || true
  sudo ip netns del blue 2>/dev/null || true
  sudo ip netns del red 2>/dev/null || true
}

trap cleanup EXIT

# Check for required commands before starting the lab
for cmd in sudo ip ping curl python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $cmd" >&2
    exit 1
  }
done

cleanup

sudo ip netns add blue
sudo ip netns add red

sudo ip link add veth-blue type veth peer name veth-red
sudo ip link set veth-blue netns blue
sudo ip link set veth-red netns red

sudo ip -n blue addr add 10.10.10.1/24 dev veth-blue
sudo ip -n red addr add 10.10.10.2/24 dev veth-red
sudo ip -n blue link set lo up
sudo ip -n red link set lo up
sudo ip -n blue link set veth-blue up
sudo ip -n red link set veth-red up

sudo ip netns exec blue ping -c 2 10.10.10.2

sudo ip netns exec red bash -lc 'python3 -m http.server 8080 --bind 10.10.10.2 >/tmp/netns_http.log 2>&1 & echo $! >/tmp/netns_http.pid'

ready=0
# Fix note:
# Earlier version could intermittently fail/hang at HTTP check because curl was executed
# before python http.server finished binding to 10.10.10.2:8080 (startup race).
# Current approach: readiness loop with short timeout retries, then a bounded curl -I.
for _ in {1..20}; do
  if sudo ip netns exec blue curl -fsS --max-time 1 -o /dev/null http://10.10.10.2:8080; then
    ready=1
    break
  fi
  sleep 0.2
done

if (( ! ready )); then
  echo "ERROR: HTTP server in red namespace did not become ready in time" >&2
  sudo ip netns exec red bash -lc 'tail -n 30 /tmp/netns_http.log' 2>/dev/null || true
  exit 1
fi

sudo ip netns exec blue curl -sS --max-time 3 -I http://10.10.10.2:8080 | sed -n '1,5p'

echo "[OK] netns mini-lab completed"
