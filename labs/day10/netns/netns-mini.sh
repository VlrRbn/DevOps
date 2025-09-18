#!/usr/bin/env bash
# netns_lab: host(10.10.0.1) <-> ns(lab10:10.10.0.2) + NAT
set -Eeuo pipefail

NS="lab10"
SUB="10.10.0"
GW="${SUB}.1"
NSIP="${SUB}.2"
WAN_IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"

cmd="${1:-}"; shift || true
[ -n "${WAN_IF:-}" ] || { echo "No default WAN iface"; ip -o -4 route show; exit 1; }

case "${cmd}" in
  up)
    mkdir -p "$HOME/labs/day10/captures"
    sudo ip netns del "$NS" 2>/dev/null || true
    sudo ip link del veth0 2>/dev/null || true

    sudo ip netns add "$NS"
    sudo ip link add veth0 type veth peer name veth1
    sudo ip link set veth1 netns "$NS"

    sudo ip addr add "${GW}/24" dev veth0 2>/dev/null || true
    sudo ip link set veth0 up
    sudo ip -n "$NS" addr add "${NSIP}/24" dev veth1
    sudo ip -n "$NS" link set lo up
    sudo ip -n "$NS" link set veth1 up
    sudo ip -n "$NS" route add default via "$GW"

    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null

    # NAT + FORWARD (idempotent)
    sudo iptables -t nat -C POSTROUTING -s "${SUB}.0/24" -o "$WAN_IF" -j MASQUERADE 2>/dev/null || \
    sudo iptables -t nat -A POSTROUTING -s "${SUB}.0/24" -o "$WAN_IF" -j MASQUERADE
    sudo iptables -C FORWARD -i veth0 -o "$WAN_IF" -s "${SUB}.0/24" -j ACCEPT 2>/dev/null || \
    sudo iptables -A FORWARD -i veth0 -o "$WAN_IF" -s "${SUB}.0/24" -j ACCEPT
    sudo iptables -C FORWARD -i "$WAN_IF" -o veth0 -d "${SUB}.0/24" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
    sudo iptables -A FORWARD -i "$WAN_IF" -o veth0 -d "${SUB}.0/24" -m state --state ESTABLISHED,RELATED -j ACCEPT

    echo "UP: ${NS} via ${WAN_IF} (${GW} -> ${NSIP})"
  ;;

  pfwd-on)
    # host:8080 -> ${NSIP}:8080 (external + localhost)
    sudo iptables -t nat -C PREROUTING -p tcp --dport 8080 -j DNAT --to-destination "${NSIP}:8080" 2>/dev/null || \
    sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination "${NSIP}:8080"
    sudo iptables -C FORWARD -p tcp -d "${NSIP}" --dport 8080 -j ACCEPT 2>/dev/null || \
    sudo iptables -A FORWARD -p tcp -d "${NSIP}" --dport 8080 -j ACCEPT
    sudo iptables -t nat -C OUTPUT -p tcp -d 127.0.0.1 --dport 8080 -j DNAT --to-destination "${NSIP}:8080" 2>/dev/null || \
    sudo iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 --dport 8080 -j DNAT --to-destination "${NSIP}:8080"
    echo "PFWD ON: host:8080 -> ${NSIP}:8080"
  ;;

  pfwd-off)
    sudo iptables -t nat -D PREROUTING -p tcp --dport 8080 -j DNAT --to-destination "${NSIP}:8080" 2>/dev/null || true
    sudo iptables -D FORWARD -p tcp -d "${NSIP}" --dport 8080 -j ACCEPT 2>/dev/null || true
    sudo iptables -t nat -D OUTPUT -p tcp -d 127.0.0.1 --dport 8080 -j DNAT --to-destination "${NSIP}:8080" 2>/dev/null || true
    echo "PFWD OFF"
  ;;

  serve)
    # start/restart HTTP in ns
    sudo ip netns exec "$NS" bash -lc 'pkill -f "http.server 8080" 2>/dev/null || true; nohup python3 -m http.server 8080 -b 0.0.0.0 >/dev/null 2>&1 &'
    sleep 0.3
    echo "HTTP in ns on ${NSIP}:8080"
  ;;

  status)
    echo "WAN_IF=$WAN_IF  NS=$NS  GW=$GW  NSIP=$NSIP"
    ip -br link | grep -E 'veth0|veth1' || true
    echo "-- host veth0 --"; ip -4 addr show veth0 || true
    echo "-- ns veth1 --";  sudo ip netns exec "$NS" ip -4 addr show veth1 2>/dev/null || echo "(ns missing)"
    echo "-- ns route --";  sudo ip netns exec "$NS" ip route 2>/dev/null || true
    echo "-- NAT --";       sudo iptables -t nat -vnL | sed -n '1,80p'
    echo "-- FORWARD --";   sudo iptables -vnL FORWARD
  ;;

  down)
    # remove pfwd if present
    "$0" pfwd-off || true
    # remove NAT + FORWARD
    sudo iptables -D FORWARD -i veth0 -o "$WAN_IF" -s "${SUB}.0/24" -j ACCEPT 2>/dev/null || true
    sudo iptables -D FORWARD -i "$WAN_IF" -o veth0 -d "${SUB}.0/24" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    sudo iptables -t nat -D POSTROUTING -s "${SUB}.0/24" -o "$WAN_IF" -j MASQUERADE 2>/dev/null || true
    # links/ns
    sudo ip netns del "$NS" 2>/dev/null || true
    sudo ip link del veth0 2>/dev/null || true
    echo "DOWN: ${NS}"
  ;;

  ""|-h|--help|help)
    echo "Usage: $0 {up|pfwd-on|pfwd-off|serve|status|down}"
  ;;

  *)
    echo "Unknown cmd: $cmd"; echo "Usage: $0 {up|pfwd-on|pfwd-off|serve|status|down}"; exit 1
  ;;
esac
