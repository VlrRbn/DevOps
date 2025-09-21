#!/usr/bin/env bash
set -Eeuo pipefail

# Configs
IFS=$'\n\t'
NS="${NS:-lab11}"
VETH_HOST="${VETH_HOST:-veth0}"
VETH_NS="${VETH_NS:-veth1}"
SUBNET="${SUBNET:-10.10.0.0/24}"
HOST_VETH_IP="${HOST_VETH_IP:-10.10.0.1}"
NS_IP="${NS_IP:-10.10.0.2}"
PORT="${PORT:-8080}"
# IF="$(detect_if)"
# HOST_EXT_IP="$(detect_host_ext_ip "$IF")"
# PCAP_DIR="${PCAP_DIR:-$HOME/labs/day11/captures}"
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || id -un)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
PCAP_DIR="${PCAP_DIR:-${REAL_HOME}/labs/day11/captures}"

# My helpers
log(){ echo -e "[$(date +%H:%M:%S)] $*"; }
die(){ echo "ERROR: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null || die "Missing binary: $1"; }

detect_if(){
  ip -o route show to default | awk '{print $5; exit}'
}

detect_host_ext_ip(){
  local ifc="${1:-$(detect_if)}"
  ip -4 -o addr show "$ifc" | awk '{print $4}' | cut -d/ -f1 | head -1
}

ensure_bins(){
  for b in ip nft sysctl awk sed cut grep tee curl python3; do need "$b"; done
}

# Actions
do_up(){
  ensure_bins
  mkdir -p "$PCAP_DIR"

  local IF
  IF="$(detect_if)"

  local HOST_EXT_IP
  HOST_EXT_IP="$(detect_host_ext_ip "$IF")"
  
  log "#1 IF=$IF  HOST_EXT_IP=${HOST_EXT_IP:-N/A}"

  # Clean start
  ip netns del "$NS" 2>/dev/null || true
  ip link del "$VETH_HOST" 2>/dev/null || true
  pkill -f 'python3 -m http.server' 2>/dev/null || true

  # Veth & netns
  log "#2 Create veth pair + netns"
  ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
  ip addr add "${HOST_VETH_IP}/24" dev "$VETH_HOST"
  ip link set "$VETH_HOST" up
  ip netns add "$NS"
  ip link set "$VETH_NS" netns "$NS"
  ip -n "$NS" addr add "${NS_IP}/24" dev "$VETH_NS"
  ip -n "$NS" link set lo up
  ip -n "$NS" link set "$VETH_NS" up
  ip -n "$NS" route add default via "$HOST_VETH_IP"
  ip netns exec "$NS" bash -lc 'echo nameserver 1.1.1.1 >/etc/resolv.conf'

  # sysctl toggles
  log "#3 Enable ip_forward=1 and route_localnet=1 (scoped to ${VETH_HOST})"
  echo 'net.ipv4.ip_forward=1' | tee /etc/sysctl.d/99-lab11.conf >/dev/null
  echo "net.ipv4.conf.${VETH_HOST}.route_localnet=1" | tee /etc/sysctl.d/99-lab11-route-localnet.conf >/dev/null
  sysctl --system >/dev/null
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  sysctl -w "net.ipv4.conf.${VETH_HOST}.route_localnet=1" >/dev/null

  # Test-server in ns
  log "#4 Start python http.server on ${NS_IP}:${PORT}"
  ip netns exec "$NS" nohup python3 -m http.server "$PORT" --bind "$NS_IP" >/dev/null 2>&1 &

  # nftables ruleset
  log "#5 Apply nftables rules (DNAT localhost/hairpin -> ns, SNAT replies, MASQUERADE)"
  cat <<EOF | tee /tmp/lab11.nft >/dev/null
flush ruleset

table ip nat {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "${IF}" tcp dport ${PORT} dnat to ${NS_IP}:${PORT}          # External access
  }
  chain output {
    type nat hook output priority dstnat; policy accept;
    ip daddr 127.0.0.1 tcp dport ${PORT} dnat to ${NS_IP}:${PORT}       # localhost -> ns
    ip daddr ${HOST_EXT_IP} tcp dport ${PORT} dnat to ${NS_IP}:${PORT}  # hairpin to host IP
    ip daddr 127.0.0.1 tcp dport ${PORT} counter dnat to ${NS_IP}:${PORT}
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr ${NS_IP} tcp dport ${PORT} snat to ${HOST_VETH_IP}         # explicit SNAT for replies
    ip saddr ${SUBNET} oifname != "lo" masquerade                       # general MASQUERADE
  }
}
EOF

  nft -f /tmp/lab11.nft
  nft list ruleset
}

do_trace(){
  # Add temporary rule to set nftrace before DNAT
  log "#6 Enable nftrace for 127.0.0.1:${PORT} (temp rule at top of ip nat output)"
  nft insert rule ip nat output position 0 ip daddr 127.0.0.1 tcp dport ${PORT} meta nftrace set 1

  # Trace hairpin to host external IP
  local IF
  IF="$(detect_if)"
  local HOST_EXT_IP; HOST_EXT_IP="$(detect_host_ext_ip "$IF")"
  if [[ -n "${HOST_EXT_IP}" ]]; then
    nft insert rule ip nat output position 0 ip daddr ${HOST_EXT_IP} tcp dport ${PORT} meta nftrace set 1 || true
  fi

  echo
  echo "Run in TERMINAL A: sudo nft monitor trace"
  echo "Run in TERMINAL B: curl -sI http://127.0.0.1:${PORT} >/dev/null"
  echo "Then remove temp rules:"
  echo "sudo nft -a list chain ip nat output | awk '/nftrace/{print \"nft delete rule ip nat output handle \"\$NF}' | sudo bash"
}

do_capture(){
  local IF
  IF="$(detect_if)"
  sudo mkdir -p "$PCAP_DIR"
  local OUT="${PCAP_DIR}/http_$(date +%H%M%S).pcap"
  log "#7 Capturing 5s on IF=${IF} to ${OUT} (port ${PORT})"
  timeout 5 tcpdump -i veth0 -nn -w "$OUT" "tcp port ${PORT}" || true
  chown "$REAL_USER":"$REAL_USER" "$OUT" 2>/dev/null || true
  log "#8 Quick read:"
  tcpdump -nn -r "$OUT" | head || true
}

do_status(){
  echo '--- nft ruleset:'; nft list ruleset || true
  echo '--- netns:'; ip netns list || true
  echo '--- links (grep veth|lab):'; ip -o link show | grep -E 'veth|l11|lab' || echo "(none)"
  echo '--- ip_forward:'; sysctl net.ipv4.ip_forward || true
  echo '--- route_localnet:'; sysctl "net.ipv4.conf.${VETH_HOST}.route_localnet" || true
}

do_down(){
  log "#9 Stopping http.server…"
  ip netns exec "$NS" pkill -f 'python3 -m http.server' 2>/dev/null || true
  pkill -f 'python3 -m http.server' 2>/dev/null || true

  log "#10 Flush nft ruleset…"
  nft flush ruleset 2>/dev/null || true

  log "#11 Revert sysctls…"
  rm -f /etc/sysctl.d/99-lab11.conf /etc/sysctl.d/99-lab11-route-localnet.conf
  sysctl -w "net.ipv4.conf.${VETH_HOST}.route_localnet=0" >/dev/null 2>&1 || true
  sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1 || true
  sysctl --system >/dev/null 2>&1 || true

  log "#12 Delete netns & veth…"
  ip netns del "$NS" 2>/dev/null || true
  ip link del "$VETH_HOST" 2>/dev/null || true

  do_status

  log "#13 DOWN complete"
}

usage(){
  cat <<USAGE
Usage: sudo $0 <up|trace|capture|status|down>

  up       - create netns/veth, enable sysctls, start server, apply nft, tests
  trace    - add temporary nftrace rules and show how to monitor
  capture  - capture 5s pcap on default IF (443 or ${PORT}); show summary
  status   - show nft ruleset, netns, veth, sysctls
  down     - stop server, flush nft, delete netns/veth, revert sysctls

Examples:
  sudo $0 up
  sudo $0 trace   # in another terminal run 'sudo nft monitor trace' and do curl
  sudo $0 capture
  sudo $0 status
  sudo $0 down
USAGE
}

main(){
  [[ $# -ge 1 ]] || { usage; exit 1; }
  case "$1" in
    up) do_up ;;
    trace) do_trace ;;
    capture) do_capture ;;
    status) do_status ;;
    down) do_down ;;
    *) usage; exit 1 ;;
  esac
}
main "$@"