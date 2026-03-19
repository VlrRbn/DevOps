#!/usr/bin/env bash
# Description: Build netns lab and apply nftables NAT/DNAT ruleset.
# Usage: setup-nft-netns.sh [--ns NAME] [--subnet CIDR24] [--host-ip IP] [--ns-ip IP] [--port N]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  setup-nft-netns.sh [--ns NAME] [--subnet CIDR24] [--host-ip IP] [--ns-ip IP] [--port N]

Defaults:
  --ns lab11
  --subnet 10.10.0.0/24
  --host-ip 10.10.0.1
  --ns-ip 10.10.0.2
  --port 8080

Examples:
  ./lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh
  ./lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh --ns lab11 --port 8080
USAGE
}

NS="lab11"
SUBNET="10.10.0.0/24"
HOST_VETH_IP="10.10.0.1"
NS_IP="10.10.0.2"
PORT="8080"
VETH_HOST="veth0"
VETH_NS="veth1"
STATE_FILE="/tmp/lesson11_nft_state.env"
RULESET_FILE="/tmp/lesson11.nft"

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
    --host-ip) HOST_VETH_IP="${2:-}"; shift 2 ;;
    --ns-ip) NS_IP="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$NS" && -n "$SUBNET" && -n "$HOST_VETH_IP" && -n "$NS_IP" ]] || { echo "ERROR: empty required argument" >&2; exit 2; }
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "ERROR: --port must be integer" >&2; exit 2; }

for cmd in sudo ip nft iptables sysctl python3 curl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

# Detect outbound interface and host external IPv4 for optional hairpin rule.
IF="$(ip -o route show to default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
[[ -n "$IF" ]] || { echo "ERROR: failed to detect outbound interface" >&2; exit 1; }
HOST_EXT_IP="$(ip -4 -o addr show "$IF" | awk '{print $4}' | cut -d/ -f1 | head -1)"

PREV_IPF="$(sysctl -n net.ipv4.ip_forward || echo 0)"
PREV_RLN="$(sysctl -n net.ipv4.conf.$VETH_HOST.route_localnet 2>/dev/null || echo 0)"

echo "[INFO] NS=$NS IF=$IF SUBNET=$SUBNET HOST_VETH_IP=$HOST_VETH_IP NS_IP=$NS_IP PORT=$PORT HOST_EXT_IP=${HOST_EXT_IP:-N/A}"

# Clean leftover lab artifacts from previous run.
sudo ip netns del "$NS" 2>/dev/null || true
if ip link show "$VETH_HOST" >/dev/null 2>&1; then
  sudo ip link del "$VETH_HOST" 2>/dev/null || true
fi

# Build host<->namespace topology.
sudo ip netns add "$NS"
sudo ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
sudo ip link set "$VETH_NS" netns "$NS"

sudo ip addr add "$HOST_VETH_IP/24" dev "$VETH_HOST"
sudo ip link set "$VETH_HOST" up

sudo ip -n "$NS" addr add "$NS_IP/24" dev "$VETH_NS"
sudo ip -n "$NS" link set "$VETH_NS" up
sudo ip -n "$NS" link set lo up
sudo ip -n "$NS" route add default via "$HOST_VETH_IP"

# Enable routing and localhost hairpin support for this lab.
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
sudo sysctl -w "net.ipv4.conf.$VETH_HOST.route_localnet=1" >/dev/null

# Ensure forward path is allowed even when host FORWARD policy is DROP (common with Docker/UFW).
sudo iptables -C FORWARD -i "$VETH_HOST" -o "$IF" -s "$SUBNET" -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -i "$VETH_HOST" -o "$IF" -s "$SUBNET" -j ACCEPT

# Allow established/related return traffic from IF to VETH_HOST for the lab subnet.
sudo iptables -C FORWARD -i "$IF" -o "$VETH_HOST" -d "$SUBNET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -i "$IF" -o "$VETH_HOST" -d "$SUBNET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Configure DNS and start demo HTTP server in namespace.
sudo ip netns exec "$NS" bash -lc 'echo nameserver 1.1.1.1 >/etc/resolv.conf'
sudo ip netns exec "$NS" bash -lc "python3 -m http.server $PORT --bind $NS_IP >/tmp/${NS}_http.log 2>&1 & echo \$! >/tmp/${NS}_http.pid"

# Build nftables NAT ruleset for namespace egress + host ingress/localhost DNAT.
cat > "$RULESET_FILE" <<NFT
# lesson11 nftables NAT/DNAT lab rules

table ip nat {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "$IF" tcp dport $PORT counter dnat to $NS_IP:$PORT
  }

  chain output {
    type nat hook output priority dstnat; policy accept;
    ip daddr 127.0.0.1 tcp dport $PORT counter dnat to $NS_IP:$PORT
NFT

# Optional hairpin rule for testing with host external IP (curl to IF IP from host).
if [[ -n "$HOST_EXT_IP" ]]; then
  cat >> "$RULESET_FILE" <<NFT
    ip daddr $HOST_EXT_IP tcp dport $PORT counter dnat to $NS_IP:$PORT
NFT
fi

# Continue building postrouting chain for SNAT/masquerade of namespace egress traffic.
cat >> "$RULESET_FILE" <<NFT
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr $NS_IP tcp dport $PORT counter snat to $HOST_VETH_IP
    ip saddr $SUBNET oifname != "lo" counter masquerade
  }
}
NFT

# Apply only ip nat table for this lesson to avoid touching unrelated rules.
sudo nft delete table ip nat 2>/dev/null || true
sudo nft -f "$RULESET_FILE"

# Save state for check/cleanup scripts.
cat > "$STATE_FILE" <<STATE
NS="$NS"
SUBNET="$SUBNET"
HOST_VETH_IP="$HOST_VETH_IP"
NS_IP="$NS_IP"
PORT="$PORT"
VETH_HOST="$VETH_HOST"
VETH_NS="$VETH_NS"
IF="$IF"
HOST_EXT_IP="${HOST_EXT_IP:-}"
PREV_IPF="$PREV_IPF"
PREV_RLN="$PREV_RLN"
RULESET_FILE="$RULESET_FILE"
STATE

echo "[OK] setup completed"
echo "[INFO] state file: $STATE_FILE"
echo "[INFO] quick test: curl -sI http://127.0.0.1:$PORT | head -n 3"
