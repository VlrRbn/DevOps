#!/usr/bin/env bash
# Description: Build a netns lab, enable NAT + DNAT (8080), and start HTTP server in namespace.
# Usage: setup-netns-nat.sh [--ns NAME] [--subnet CIDR24] [--host-ip IP] [--ns-ip IP] [--port N]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  setup-netns-nat.sh [--ns NAME] [--subnet CIDR24] [--host-ip IP] [--ns-ip IP] [--port N]

Defaults:
  --ns lab10
  --subnet 10.10.0.0/24
  --host-ip 10.10.0.1
  --ns-ip 10.10.0.2
  --port 8080

Examples:
  ./lessons/10-networking-nat-dnat-netns-ufw/scripts/setup-netns-nat.sh
  ./lessons/10-networking-nat-dnat-netns-ufw/scripts/setup-netns-nat.sh --ns lab10 --port 8080
USAGE
}

NS="lab10"
SUBNET="10.10.0.0/24"
HOST_IP="10.10.0.1"
NS_IP="10.10.0.2"
PORT="8080"
VETH_HOST="veth0"
VETH_NS="veth1"
STATE_FILE="/tmp/lesson10_netns_state.env"

# Parse and validate user input.
for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    usage
    exit 0
  fi
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ns) NS="${2:-}"; shift 2 ;;
    --subnet) SUBNET="${2:-}"; shift 2 ;;
    --host-ip) HOST_IP="${2:-}"; shift 2 ;;
    --ns-ip) NS_IP="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$NS" && -n "$SUBNET" && -n "$HOST_IP" && -n "$NS_IP" ]] || { echo "ERROR: invalid empty argument" >&2; exit 2; }
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "ERROR: --port must be integer" >&2; exit 2; }

# Ensure required runtime tools are available.
for cmd in sudo ip iptables sysctl curl python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

# Detect outbound interface and snapshot sysctl values to restore later.
IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
[[ -n "$IF" ]] || { echo "ERROR: failed to detect outbound interface" >&2; exit 1; }

PREV_IPF="$(sysctl -n net.ipv4.ip_forward || echo 0)"
PREV_RLN="$(sysctl -n net.ipv4.conf.$VETH_HOST.route_localnet 2>/dev/null || echo 0)"

echo "[INFO] NS=$NS IF=$IF SUBNET=$SUBNET HOST_IP=$HOST_IP NS_IP=$NS_IP PORT=$PORT"

# Start from clean namespace/veth if leftovers exist.
sudo ip netns del "$NS" 2>/dev/null || true
ip link show "$VETH_HOST" >/dev/null 2>&1 && sudo ip link del "$VETH_HOST" 2>/dev/null || true

# Build host<->namespace topology and L3 addressing.
sudo ip netns add "$NS"
sudo ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
sudo ip link set "$VETH_NS" netns "$NS"

sudo ip addr add "$HOST_IP/24" dev "$VETH_HOST"
sudo ip link set "$VETH_HOST" up

sudo ip -n "$NS" addr add "$NS_IP/24" dev "$VETH_NS"
sudo ip -n "$NS" link set "$VETH_NS" up
sudo ip -n "$NS" link set lo up
sudo ip -n "$NS" route add default via "$HOST_IP"

# Turn host into router for namespace traffic.
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
sudo sysctl -w "net.ipv4.conf.$VETH_HOST.route_localnet=1" >/dev/null

# Why commands look "repeated":
# We intentionally use idempotent pattern "-C rule || -A rule".
# -C checks if rule already exists, -A adds it only when missing.
# This allows safe re-run of setup script without duplicate iptables rules.
# Also note these are different chains/flows: POSTROUTING, FORWARD, PREROUTING, OUTPUT.

# This rule enables NAT for all outgoing traffic from NS subnet to outside world via IF.
sudo iptables -t nat -C POSTROUTING -s "$SUBNET" -o "$IF" -j MASQUERADE 2>/dev/null || \
  sudo iptables -t nat -A POSTROUTING -s "$SUBNET" -o "$IF" -j MASQUERADE

# This rule allows forwarding traffic from VETH_HOST to IF when it's sourced from NS subnet.
sudo iptables -C FORWARD -i "$VETH_HOST" -o "$IF" -s "$SUBNET" -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -i "$VETH_HOST" -o "$IF" -s "$SUBNET" -j ACCEPT

# This rule allows return traffic from IF to VETH_HOST when it's part of established connection with NS.
sudo iptables -C FORWARD -i "$IF" -o "$VETH_HOST" -d "$SUBNET" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -i "$IF" -o "$VETH_HOST" -d "$SUBNET" -m state --state ESTABLISHED,RELATED -j ACCEPT

# This rule allows incoming traffic to host:PORT to be DNATed to NS:PORT.
sudo iptables -t nat -C PREROUTING -p tcp --dport "$PORT" -j DNAT --to-destination "$NS_IP:$PORT" 2>/dev/null || \
  sudo iptables -t nat -A PREROUTING -p tcp --dport "$PORT" -j DNAT --to-destination "$NS_IP:$PORT"

# This rule allows forwarded packets to NS on $PORT to be accepted by host firewall.
sudo iptables -C FORWARD -p tcp -d "$NS_IP" --dport "$PORT" -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -p tcp -d "$NS_IP" --dport "$PORT" -j ACCEPT

# This is the key DNAT rule that allows accessing NS service via localhost:PORT on host.
sudo iptables -t nat -C OUTPUT -p tcp --dport "$PORT" -d 127.0.0.1 -j DNAT --to-destination "$NS_IP:$PORT" 2>/dev/null || \
  sudo iptables -t nat -A OUTPUT -p tcp --dport "$PORT" -d 127.0.0.1 -j DNAT --to-destination "$NS_IP:$PORT"

# This is a bit special: when traffic is DNATed from localhost to NS, the source IP is still localhost
sudo iptables -t nat -C POSTROUTING -o "$VETH_HOST" -p tcp -d "$NS_IP" --dport "$PORT" -j SNAT --to-source "$HOST_IP" 2>/dev/null || \
  sudo iptables -t nat -A POSTROUTING -o "$VETH_HOST" -p tcp -d "$NS_IP" --dport "$PORT" -j SNAT --to-source "$HOST_IP"

# Prepare namespace DNS and start demo HTTP endpoint.
sudo ip netns exec "$NS" bash -lc 'echo nameserver 1.1.1.1 >/etc/resolv.conf'
sudo ip netns exec "$NS" bash -lc "python3 -m http.server $PORT --bind $NS_IP >/tmp/${NS}_http.log 2>&1 & echo \$! >/tmp/${NS}_http.pid"

# Persist state for check/cleanup scripts.
cat > "$STATE_FILE" <<STATE
NS="$NS"
VETH_HOST="$VETH_HOST"
VETH_NS="$VETH_NS"
SUBNET="$SUBNET"
HOST_IP="$HOST_IP"
NS_IP="$NS_IP"
PORT="$PORT"
IF="$IF"
PREV_IPF="$PREV_IPF"
PREV_RLN="$PREV_RLN"
STATE

echo "[OK] setup completed"
echo "[INFO] state file: $STATE_FILE"
echo "[INFO] test: sudo ip netns exec $NS ping -c 1 $HOST_IP"
echo "[INFO] test: curl -sI http://127.0.0.1:$PORT | head -n 5"
