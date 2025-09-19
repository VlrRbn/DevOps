#!/usr/bin/env bash
# iproute2, iptables (legacy), tcpdump, curl, python3.
set -euo pipefail

DUR="${1:-10}"
NS="lab10"
VETH_HOST="veth0"
VETH_NS="veth1"
HOST_IP="10.10.0.1/24"
NS_IP="10.10.0.2/24"
NS_GW="10.10.0.1"
PCAP_DIR="$HOME/labs/day10/captures"

mkdir -p "$PCAP_DIR"

: "${IF:=any}"

say() { printf "==> %s\n" "$*"; }

PREV_IPF="$(sysctl -n net.ipv4.ip_forward || true)"
PREV_RLN="$(sysctl -n net.ipv4.conf.$VETH_HOST.route_localnet 2>/dev/null || echo "")"

UFW_ACTIVE=0
UFW_ADDED_8080=0
if command -v ufw >/dev/null 2>&1; then
  if sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
    UFW_ACTIVE=1
  fi
fi

cleanup() {
  set +e
  say "Cleanup"

  # UFW: delete only 8080
  if [ "$UFW_ACTIVE" -eq 1 ] && [ "$UFW_ADDED_8080" -eq 1 ]; then
    yes | sudo ufw delete allow 8080/tcp >/dev/null 2>&1
  fi

  # iptables: delete all rules
  sudo iptables -t nat -C PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null \
  && sudo iptables -t nat -D PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 || true

  sudo iptables -C FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT 2>/dev/null \
  && sudo iptables -D FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT || true

  sudo iptables -t nat -C OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null \
  && sudo iptables -t nat -D OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080 || true

  sudo iptables -t nat -C POSTROUTING -o "$VETH_HOST" -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1 2>/dev/null \
  && sudo iptables -t nat -D POSTROUTING -o "$VETH_HOST" -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1 || true

  sudo iptables -t nat -C POSTROUTING -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1 2>/dev/null \
  && sudo iptables -t nat -D POSTROUTING -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1 || true

  sudo iptables -t nat -C OUTPUT -p tcp -d 127.0.0.1 --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null \
  && sudo iptables -t nat -D OUTPUT -p tcp -d 127.0.0.1 --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 || true

  sudo iptables -t nat -C POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE 2>/dev/null \
  && sudo iptables -t nat -D POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE || true

  sudo iptables -C FORWARD -i "$IF" -o "$VETH_HOST" -d 10.10.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
  && sudo iptables -D FORWARD -i "$IF" -o "$VETH_HOST" -d 10.10.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT || true

  sudo iptables -C FORWARD -i "$VETH_HOST" -o "$IF" -s 10.10.0.0/24 -j ACCEPT 2>/dev/null \
  && sudo iptables -D FORWARD -i "$VETH_HOST" -o "$IF" -s 10.10.0.0/24 -j ACCEPT || true

  # kill HTTP-server
  if sudo ip netns pids "$NS" >/dev/null 2>&1; then
    PID=$(sudo ip netns exec "$NS" bash -lc 'cat /tmp/http.pid 2>/dev/null' || true)
    if [ -n "${PID:-}" ]; then
      sudo ip netns exec "$NS" kill "$PID" 2>/dev/null
    fi
  fi

  # delete netns & veth
  sudo ip netns del "$NS" 2>/dev/null || true
  ip link show "$VETH_HOST" >/dev/null 2>&1 && sudo ip link del "$VETH_HOST" 2>/dev/null

  # sysctl like was
  if [ -n "${PREV_IPF:-}" ]; then
    sudo sysctl -w net.ipv4.ip_forward="$PREV_IPF" >/dev/null 2>&1
  fi
  if [ -n "${PREV_RLN:-}" ]; then
    sudo sysctl -w "net.ipv4.conf.$VETH_HOST.route_localnet=$PREV_RLN" >/dev/null 2>&1
  else
    # if iface not exist reset to 0
    sudo sysctl -w "net.ipv4.conf.$VETH_HOST.route_localnet=0" >/dev/null 2>&1 || true
  fi

  say "#14 - sysctl like new"
}
trap cleanup EXIT

# setup
say "#1 - Create namespace и vet"
sudo ip netns del "$NS" 2>/dev/null || true
sudo ip netns add "$NS"
sudo ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
sudo ip link set "$VETH_NS" netns "$NS"

sudo ip addr add "$HOST_IP" dev "$VETH_HOST"
sudo ip link set "$VETH_HOST" up

sudo ip -n "$NS" addr add "$NS_IP" dev "$VETH_NS"
sudo ip -n "$NS" link set "$VETH_NS" up
sudo ip -n "$NS" link set lo up
sudo ip -n "$NS" route add default via "$NS_GW"

say "#2 - Check connect"
sudo ip netns exec "$NS" ping -c 1 "$NS_GW" >/dev/null

say "#3 - Turn on routing & localnet"
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
sudo sysctl -w "net.ipv4.conf.$VETH_HOST.route_localnet=1" >/dev/null
sudo sysctl -w net.ipv4.conf.all.route_localnet=1

say "#4 - NAT & forwarding"
sudo iptables -t nat -C POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE 2>/dev/null \
  || sudo iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE

sudo iptables -C FORWARD -i "$VETH_HOST" -o "$IF" -s 10.10.0.0/24 -j ACCEPT 2>/dev/null \
  || sudo iptables -A FORWARD -i "$VETH_HOST" -o "$IF" -s 10.10.0.0/24 -j ACCEPT

sudo iptables -C FORWARD -i "$IF" -o "$VETH_HOST" -d 10.10.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
  || sudo iptables -A FORWARD -i "$IF" -o "$VETH_HOST" -d 10.10.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT

say "#5 - DNS in namespace"
sudo ip netns exec "$NS" bash -lc 'echo nameserver 1.1.1.1 >/etc/resolv.conf'

say "#6 - Outside IP from ns:"; sudo ip netns exec "$NS" curl -sS https://ifconfig.io | head -1 || true

say "#7 - start http-server in ns on 10.10.0.2:8080…"
sudo ip netns exec "$NS" bash -lc 'command -v python3 >/dev/null && (python3 -m http.server 8080 --bind 10.10.0.2 >/dev/null 2>&1 & echo $! >/tmp/http.pid) || true'

say "#8 - DNAT on port 8080 & local on 127.0.0.1:8080…"
sudo iptables -t nat -C PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null \
  || sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080

sudo iptables -C FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT 2>/dev/null \
  || sudo iptables -A FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT

sudo iptables -t nat -C OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null \
  || sudo iptables -t nat -A OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080

sudo iptables -t nat -C POSTROUTING -o "$VETH_HOST" -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1 2>/dev/null \
  || sudo iptables -t nat -A POSTROUTING -o "$VETH_HOST" -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1

sudo iptables -t nat -C POSTROUTING -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1 2>/dev/null \
  || sudo iptables -t nat -A POSTROUTING -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1

sudo iptables -t nat -C OUTPUT -p tcp -d 127.0.0.1 --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null \
  || sudo iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 --dport 8080 -j DNAT --to-destination 10.10.0.2:8080

# UFW: if active — open 8080 (then delete)
if [ "$UFW_ACTIVE" -eq 1 ]; then
  if ! sudo ufw status | awk '{print tolower($0)}' | grep -q '8080/tcp.*allow in'; then
    say "#9 - UFW active allow  8080/tcp"
    yes | sudo ufw allow 8080/tcp >/dev/null
    UFW_ADDED_8080=1
  fi
fi

# pcap
PCAP_FILE="$PCAP_DIR/https_$(date +%H%M%S).pcap"
say "#10 - tcpdump on ${IF:-any} (tcp port 8080), ${DUR}s → $PCAP_FILE"
sudo timeout "$DUR" tcpdump -i "${IF:-any}" -nn -w "$PCAP_FILE" 'tcp port 8080' & TCPDUMP_PID=$!

sleep 1
say "#11 - check HTTP local"
for i in {1..5}; do
	curl -sI http://127.0.0.1:8080 >/dev/null || true
	sleep 1
done

wait "$TCPDUMP_PID" || true

say "#12 - pcap write in: $PCAP_FILE"
say "#13 - getting for cleanup"

# cleanup called with trap
