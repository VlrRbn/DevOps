#!/usr/bin/env bash
set -Eeuo pipefail

# clean start (silent if not)
for ns in blue red; do sudo ip netns del "$ns" 2>/dev/null || true; done

# ns + veth
sudo ip netns add blue
sudo ip netns add red
sudo ip link add veth-blue type veth peer name veth-red
sudo ip link set veth-blue netns blue
sudo ip link set veth-red  netns red
sudo ip -n blue addr add 10.10.10.1/24 dev veth-blue
sudo ip -n red  addr add 10.10.10.2/24 dev veth-red
sudo ip -n blue link set lo up
sudo ip -n red  link set lo up
sudo ip -n blue link set veth-blue up
sudo ip -n red  link set veth-red  up

# ping
sudo ip netns exec blue ping -c 2 10.10.10.2

# HTTP in red and curl from blue
sudo ip netns exec red bash -lc 'python3 -m http.server 8080 --bind 10.10.10.2 >/dev/null 2>&1 & echo $! >/tmp/http.pid'
sudo ip netns exec blue curl -sI http://10.10.10.2:8080 | head -5

# cleanup
sudo ip netns exec red bash -lc 'kill "$(cat /tmp/http.pid 2>/dev/null)" 2>/dev/null || true'
sudo ip netns del blue
sudo ip netns del red
