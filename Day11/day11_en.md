# day11_en

---

# Networking (Part 3): nftables NAT/DNAT + Persistence

**Date:** **2025-09-21**

**Topic:** nftables ruleset (tables/chains), NAT (MASQUERADE), DNAT (host→ns), hairpin, persistence via `nftables.service`, tracing & counters

---

## Goals

- Replace ad-hoc `iptables` rules with a clean **nftables** ruleset.
- Keep **NAT (10.10.0.0/24 → WAN)** and **DNAT** for `host:8080 → 10.10.0.2:8080`.
- Make rules **persistent across reboots** with `nftables.service`.
- Learn **counters** and **nft monitor trace** for fast debugging.
- Add **hairpin** for `$HOST_IP:8080` from the host itself.

---

## Pocket Cheat

| Command | What it does | Why / Example |
| --- | --- | --- |
| `sudo nft list ruleset` | Dump full ruleset | Verify tables/chains/rules |
| `sudo nft flush ruleset` | Clear ruleset (careful) | Reset lab state |
| `sudo nft -f FILE` | Load rules from file | Apply a saved ruleset |
| `sudo systemctl enable --now nftables` | Persist rules via `/etc/nftables.conf` | Auto-load on boot |
| `sudo nft list ruleset -a` | Show rules with handles | Delete rules by handle |
| `sudo nft monitor trace` | Live packet trace | See which rule accepts/dnats |
| `ip -o route show to default | awk '{print $5; exit}'` | Get WAN iface name | Use in scripts: `IF="$(ip -o route show to default | awk '{print $5; exit}')"` |
| `ip -4 -o addr show "$IF" | awk '{print $4}' | cut -d/ -f1` | Get IPv4 of `$IF` | Handy for NAT/iptables vars: `HOST_IP="$(ip -4 -o addr show "$IF" | awk '{print $4}' | cut -d/ -f1)"` |

---

## Quick Blocks

- Enable IPv4 forwarding (persistent):

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-lab11.conf
sudo sysctl --system
```

**Why:** NAT needs routing; without it, replies won’t make it back.

- Minimal **nftables** NAT+DNAT ruleset (runtime apply right now):

```bash
IF="$(ip -o route show to default | awk '{print $5; exit}')"
HOST_IP="$(ip -4 -o addr show "$IF" | awk '{print $4}' | cut -d/ -f1 | head -1)"

sudo tee /tmp/lab11.nft >/dev/null <<'NFT'
flush ruleset                                                    # **1**

table ip nat {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;       # **2**
  }
  chain output {
    type nat hook output priority -100; policy accept;           # **3**
    ip daddr 127.0.0.1 tcp dport 8080 dnat to 10.10.0.2:8080     # **4**
  }
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    ip saddr 10.10.0.0/24 oifname != "lo" masquerade             # **5**
    tcp dport 8080 ip daddr 10.10.0.2 masquerade                 # **6**
  }
}
NFT

# **1** flush ruleset at the top wipes everything (including UFW) for this session.
# **2** External DNAT example, tcp dport 8080 dnat to 10.10.0.2:8080
# **3** Local host → ns service (DNAT when connecting to 127.0.0.1:8080)
# **4** Hairpin to your host's own external IP, ip daddr __HOST_IP__ tcp dport 8080 dnat to 10.10.0.2:8080
# **5** General MASQUERADE for ns subnet via any non-loopback iface
# **6** Hairpin reply path (only if hairpin DNAT enabled)

sudo nft -f /tmp/lab11.nft
sudo nft list ruleset

curl -sI http://127.0.0.1:8080 | head     # Should hit the ns Python server
```

---

## Practice

1. Prepare folders and  shell var:

```bash
NS="lab11"
VETH_HOST="veth0"
VETH_NS="veth1"
SUBNET="10.10.0.0/24"
HOST_VETH_IP="10.10.0.1"
NS_IP="10.10.0.2"
PORT=8080
IF="$(ip -o route show to default | awk '{print $5; exit}')"
HOST_EXT_IP="$(ip -4 -o addr show "$IF" | awk '{print $4}' | cut -d/ -f1 | head -1)"
PCAP_DIR="$HOME/labs/day11/captures"
mkdir -p "$PCAP_DIR"
```

2. Clear start:

```bash
sudo ip netns del "$NS" 2>/dev/null || true
sudo ip link del "$VETH_HOST" 2>/dev/null || true
sudo pkill -f 'python3 -m http.server' 2>/dev/null || true
```

3. Veth & Namespace:

```bash
sudo ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
sudo ip addr add "${HOST_VETH_IP}/24" dev "$VETH_HOST"
sudo ip link set "$VETH_HOST" up
sudo ip netns add "$NS"
sudo ip link set "$VETH_NS" netns "$NS"
sudo ip -n "$NS" addr add "${NS_IP}/24" dev "$VETH_NS"
sudo ip -n "$NS" link set lo up
sudo ip -n "$NS" link set "$VETH_NS" up
sudo ip -n "$NS" route add default via "$HOST_VETH_IP"
sudo ip netns exec "$NS" bash -lc 'echo nameserver 1.1.1.1 >/etc/resolv.conf'
```

4. System switches: ip_forward + route_localnet (`veth0`):

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-lab11.conf >/dev/null
echo "net.ipv4.conf.${VETH_HOST}.route_localnet=1" | sudo tee /etc/sysctl.d/99-lab11-route-localnet.conf >/dev/null
sudo sysctl --system >/dev/null
```

5. Test-serveir in ns:

```bash
sudo ip netns exec "$NS" nohup python3 -m http.server "$PORT" --bind "$NS_IP" >/dev/null 2>&1 &
```

6. nftables: DNAT localhost->ns, explicit SNAT responses, MASQUERADE for subnet:

```bash
sudo tee /tmp/lab11.nft >/dev/null <<NFT
flush ruleset

table ip nat {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;
    iifname "${IF}" tcp dport ${PORT} dnat to ${NS_IP}:${PORT}     # External access
  }
  chain output {
    type nat hook output priority -100; policy accept;
    ip daddr 127.0.0.1 tcp dport ${PORT} dnat to ${NS_IP}:${PORT}
    ip daddr ${HOST_EXT_IP} tcp dport ${PORT} dnat to ${NS_IP}:${PORT}     # hairpin to host IP
  }
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    ip daddr ${NS_IP} tcp dport ${PORT} snat to ${HOST_VETH_IP}
    ip saddr ${SUBNET} oifname != "lo" masquerade
  }
}
NFT

sudo nft -f /tmp/lab11.nft
sudo nft list ruleset
```

7. Quick check:

```bash
sudo ip netns exec "$NS" curl -sI "http://${NS_IP}:${PORT}" | sed -n '1,3p'
# HTTP/1.0 200 OK

curl -sI "http://127.0.0.1:${PORT}" | sed -n '1,3p'
# HTTP/1.0 200 OK
```

8. Hairpin on external IP:

```bash
sudo nft add rule ip nat output ip daddr ${HOST_EXT_IP} tcp dport ${PORT} dnat to ${NS_IP}:${PORT}

sudo nft -f /tmp/lab11.nft     # Rebuild /tmp/lab11.nft with HOST_EXT_IP injected
curl -sI "http://${HOST_EXT_IP}:8080" | head
# HTTP/1.0 200 OK
```

9. Trace a single request (see which rule matches):

```bash
# In one terminal:
sudo nft monitor trace | sed -n '1,20p'

# In another:
curl -sI http://127.0.0.1:8080 >/dev/null
```

10. Capture traffic (proof):

```bash
sudo timeout 5 tcpdump -i "$IF" -nn -w "${PCAP_DIR}/https_$(date +%H%M%S).pcap" 'tcp port 443 or tcp port 8080'
tcpdump -nn -r ${PCAP_DIR}/*.pcap | head
```

11. Cleanup:

```bash
sudo ip netns exec lab11 pkill -f 'python3 -m http.server' 2>/dev/null || true
sudo pkill -f 'python3 -m http.server' 2>/dev/null || true
sudo nft flush ruleset 2>/dev/null || true
sudo ip netns del lab11 2>/dev/null || true
sudo ip link del veth0 2>/dev/null || true

sudo rm -f /etc/sysctl.d/99-lab11.conf /etc/sysctl.d/99-lab11-route-localnet.conf
sudo sysctl -w net.ipv4.conf.veth0.route_localnet=0 >/dev/null 2>&1 || true
sudo sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1 || true
sudo sysctl --system >/dev/null 2>&1 || true

echo '--- nft ruleset:'; sudo nft list ruleset || true
echo '--- netns:'; ip netns list || true
echo '--- veth on host:'; ip -o link show | grep -E 'veth|l11|lab' || echo "(none)"
echo '--- ip_forward:'; sysctl net.ipv4.ip_forward || true
```

---

## Security Checklist

- Keep **policy accept** in `nat` chains.
- Scope DNAT to specific ingress (**filter** with `iifname "$IF"`), and/or to source CIDRs (`ip saddr …`).
- Persist only **what you actually need** — no debug leftovers.
- **Bind to the exact IP**: service in ns listens on `10.10.0.2:PORT`, not `0.0.0.0`.
- **Hairpin consciously**: enable only when needed; MASQUERADE replies with host IP.
- **UFW vs nft**: either let UFW generate nft rules or manage nft manually — don’t mix both styles.
- **Pre-publish tests**: `nft monitor trace`, `tcpdump -ni any 'tcp port …'`, scripted `curl` checks.
- **Disable forwarding** when the lab is done: set `net.ipv4.ip_forward=0`.
- **Predictable names** for veth/netns (`veth-labX`, `labX`) to target rules precisely.

---

## Pitfalls

---

## Labs

---

## Notes

---

## Summary

---

## Artifacts

---

## To repeat

---

## Acceptance Criteria (self-check)