#!/usr/bin/env bash
# Description: Apply nftables NAT rules for a netns lab without touching filter/raw tables.
# Usage: netns-nft.apply.sh
# Notes: Deletes and recreates the ip nat table and prints detected IF/HOST_IP.
set -Eeuo pipefail
IF="$(ip -o route show to default | awk '{print $5; exit}')"
HOST_IP="$(ip -4 -o addr show "$IF" | awk '{print $4}' | cut -d/ -f1 | head -1)"

sudo nft -f - <<EOF
table ip nat { }        # ensure table exists
delete table ip nat     # drop only NAT table to avoid touching filter/raw
EOF

sudo nft -f - <<EOF
table ip nat {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    # iifname "$IF" tcp dport 8080 dnat to 10.10.0.2:8080           # enable for ingress
  }
  chain output {
    type nat hook output priority dstnat; policy accept;
    ip daddr 127.0.0.1 tcp dport 8080 dnat to 10.10.0.2:8080
    # ip daddr ${HOST_IP} tcp dport 8080 dnat to 10.10.0.2:8080     # hairpin
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr 10.10.0.0/24 oifname != "lo" masquerade
    tcp dport 8080 ip daddr 10.10.0.2 masquerade
  }
}
EOF

echo "Applied NAT only. IF=${IF}, HOST_IP=${HOST_IP}"
