#!/usr/bin/env bash
set -o pipefail

mkdir -p "$HOME/labs/day10"/{captures,netns}

sudo ip netns del lab10 2>/dev/null || true
sudo ip netns add lab10
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns lab10
sudo ip addr add 10.10.0.1/24 dev veth0
sudo ip link set veth0 up
sudo ip -n lab10 addr add 10.10.0.2/24 dev veth1
sudo ip -n lab10 link set veth1 up
sudo ip -n lab10 link set lo up
sudo ip -n lab10 route add default via 10.10.0.1

sudo ip netns exec lab10 ping -c 1 10.10.0.1

sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.veth0.route_localnet=1

IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
[ -n "$IF" ] || { echo "Unable to detect WAN interface"; ip -o -4 route show; exit 1; }

sudo iptables -t nat -C POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE 2>/dev/null \
  || sudo iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE

sudo ip netns exec lab10 bash -lc 'echo nameserver 1.1.1.1 >/etc/resolv.conf'

sudo ip netns exec lab10 curl -sS https://ifconfig.io | head -1

sudo ip netns exec lab10 bash -lc 'command -v python3 >/dev/null && (python3 -m http.server 8080 --bind 10.10.0.2 >/dev/null 2>&1 & echo $! >/tmp/http.pid) || true'

sudo iptables -C FORWARD -i veth0 -o "$IF" -s 10.10.0.0/24 -j ACCEPT 2>/dev/null \
  || sudo iptables -A FORWARD -i veth0 -o "$IF" -s 10.10.0.0/24 -j ACCEPT

sudo iptables -C FORWARD -i "$IF" -o veth0 -d 10.10.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
  || sudo iptables -A FORWARD -i "$IF" -o veth0 -d 10.10.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT

sudo iptables -t nat -C PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null \
  || sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080

sudo iptables -C FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT 2>/dev/null \
  || sudo iptables -A FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT

sudo iptables -t nat -C OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null \
  || sudo iptables -t nat -A OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080

sudo iptables -t nat -C POSTROUTING -o veth0 -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1 2>/dev/null \
  || sudo iptables -t nat -A POSTROUTING -o veth0 -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1

curl -sI http://127.0.0.1:8080 | head -5

sudo ufw status verbose || true
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 8080/tcp
sudo ufw allow in  on lo
sudo ufw allow out on lo
yes | sudo ufw enable
sudo ufw status numbered

sudo ip netns exec lab10 bash -c 'printf "ns IPs: "; ip -4 addr show veth1 | awk "/inet /{print \$2}"; ping -c1 -W1 1.1.1.1 && echo OK || echo FAIL'

sudo timeout 10 tcpdump -i "$IF" -nn -w "${HOME}/labs/day10/captures/https_$(date +%H%M%S).pcap" 'tcp port 443' || true

echo "All Done!"
