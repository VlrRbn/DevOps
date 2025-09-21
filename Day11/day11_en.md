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
# sudo nft delete table ip nat 2>/dev/null || true     # if UFW is active, do not flush ruleset; manage only table ip nat

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

sed -ri "s/__HOST_IP__/${HOST_IP}/" /tmp/lab11.nft     # Enable only if you really need hairpinning via external IP
sudo nft -f /tmp/lab11.nft
sudo nft list ruleset

curl -sI http://127.0.0.1:8080 | head                  # Should hit the ns Python server
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

4. System toggles: ip_forward + route_localnet (`veth0`):

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-lab11.conf >/dev/null
echo "net.ipv4.conf.${VETH_HOST}.route_localnet=1" | sudo tee /etc/sysctl.d/99-lab11-route-localnet.conf >/dev/null
sudo sysctl --system >/dev/null
```

5. Test-server in ns:

```bash
sudo ip netns exec "$NS" nohup python3 -m http.server "$PORT" --bind "$NS_IP" >/dev/null 2>&1 &
```

6. nftables: DNAT localhost->ns, explicit SNAT responses, MASQUERADE for subnet:

```bash
sudo tee /tmp/lab11.nft >/dev/null <<NFT
flush ruleset
# nft delete table ip nat 2>/dev/null || true     # if UFW is active, do not flush ruleset; manage only table ip nat

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

- Wrong `-o $IF` on MASQUERADE ⇒ NAT silent fail.
- Mixing iptables and nftables in the same lab ⇒ confusing results.
- UFW rule order (deny above allow) blocks traffic; use `ufw insert`.
- DNS missing in ns (`/etc/resolv.conf`) breaks curl/name lookups.

---

## Labs

`labs/day11/netns/netns-nft.sh` — all in one script.

```bash
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
# nft delete table ip nat 2>/dev/null || true     # if UFW is active, do not flush ruleset; manage only table ip nat

table ip nat {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "${IF}" tcp dport ${PORT} dnat to ${NS_IP}:${PORT}          # External access
  }
  chain output {
    type nat hook output priority dstnat; policy accept;
    ip daddr 127.0.0.1 tcp dport ${PORT} dnat to ${NS_IP}:${PORT}       # localhost -> ns
    ip daddr ${HOST_EXT_IP} tcp dport ${PORT} dnat to ${NS_IP}:${PORT}  # hairpin to host IP
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
  timeout 5 tcpdump -i "$VETH_HOST" -nn -w "$OUT" "tcp port ${PORT}" || true
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
```

---

## Tools

### `tools/netns-nft.apply.sh` — Only table ip nat, without flush ruleset.

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IF="$(ip -o route show to default | awk '{print $5; exit}')"
HOST_IP="$(ip -4 -o addr show "$IF" | awk '{print $4}' | cut -d/ -f1 | head -1)"

sudo nft -f - <<EOF
table ip nat { }        # ensure table exists (noop if already)
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
```

Quick NAT reloading without removing the firewall.

Add sysctls when needed:

```bash
sudo sysctl -w net.ipv4.conf.veth0.route_localnet=1     # localhost→ns
sudo sysctl -w net.ipv4.ip_forward=1                    # external ingress

sudo nft delete table ip nat 2>/dev/null || true        # cleanup
```

---

### `tools/nft-save-restore.sh` — quick persist helpers

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

usage(){ echo "Usage: $0 {save|restore|validate|flush|flush-nat|show|diff} [-y]"; exit 1; }

cmd="${1:-}"; shift || true
assume_yes="${1:-}"

case "$cmd" in
  save)
    ts="$(date +%F_%H%M%S)"
    sudo cp -a /etc/nftables.conf "/etc/nftables.conf.bak.$ts" 2>/dev/null || true
    sudo nft list ruleset | sudo tee /etc/nftables.conf >/dev/null
    sudo nft -c -f /etc/nftables.conf     # Checking the configuration for syntax
    sudo systemctl enable --now nftables
    echo "Saved live ruleset to /etc/nftables.conf (+enabled nftables). Backup: /etc/nftables.conf.bak.$ts"
    ;;

  restore)
    sudo nft -c -f /etc/nftables.conf
    sudo nft -f /etc/nftables.conf        # Apply what is in /etc/nftables.conf
    echo "Restored ruleset from /etc/nftables.conf"
    ;;

  validate)
    sudo nft -c -f /etc/nftables.conf
    echo "Config is syntactically valid."
    ;;

  flush)
    if [[ "$assume_yes" != "-y" ]]; then
      read -r -p "This will FLUSH ALL nftables rules (firewall off). Continue? [y/N] " a
      [[ "$a" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
    fi
    sudo nft flush ruleset
    echo "Flushed entire ruleset."
    ;;

  flush-nat)
  # Safer: only remove the NAT table without touching filter/raw
    sudo nft delete table ip nat 2>/dev/null || true
    echo "Deleted table ip nat (filter/raw untouched)."
    ;;

  show)
    sudo nft list ruleset
    ;;

  diff)
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    sudo nft list ruleset > "$tmp"
  # Show the difference between the live ruleset and the one in /etc/nftables.conf
    sudo diff -u "$tmp" /etc/nftables.conf || true
    ;;

  *) usage ;;
esac
```

- `restore` (apply `/etc/nftables.conf`),
- `validate` (`nft -c`),
- `flush-nat` (drop only NAT table),
- `diff` (live vs file),
- `flush -y` for non-interactive use.

```bash
# Persist live ruleset
sudo nft list ruleset | sudo tee /etc/nftables.conf >/dev/null
sudo systemctl enable --now nftables
sudo systemctl status nftables
```

---

## Notes

- iptables NAT lives in the **nat** table (`PREROUTING` for DNAT, `POSTROUTING` for MASQUERADE).
- Localhost access needs DNAT in **OUTPUT**; external ingress uses **PREROUTING**.
- Always enable IPv4 forwarding: `net.ipv4.ip_forward=1` (runtime + persistent).
- UFW controls filter chains; leave **policies** to UFW and add NAT rules separately.
- Prefer idempotent add/del (`C` check before `A`/`D`) to avoid “Bad rule”.

---

## Summary

- Built a netns (`lab11`) with veth.
- NAT (MASQUERADE) for `10.10.0.0/24` via the WAN iface.
- DNAT to expose `ns:8080` from host; verified with counters and tcpdump.
- Cleanup is idempotent; hairpin documented.

---

## Artifacts

- `tools/netns-nft.apply.sh`
- `tools/nft-save-restore.sh`
- `labs/day11/netns/netns-nft.sh`

---

## To repeat

- Recreate ns and veth; set default route and resolv.conf inside ns.
- Re-apply: MASQUERADE + DNAT + FORWARD allow.
- Send a single request, confirm counters grow in `PREROUTING`, `FORWARD`, `POSTROUTING`.
- Test hairpin via `$HOST_IP:8080`.

---

## Acceptance Criteria

- [ ]  `nft list ruleset` shows `table ip nat` with `prerouting/output/postrouting` as defined.
- [ ]  From host: `curl -I http://127.0.0.1:8080` hits the ns server.
- [ ]  `nft monitor trace` confirms DNAT in `output` and MASQUERADE in `postrouting`.
- [ ]  `curl -I http://$HOST_IP:8080` works (true hairpin).
- [ ]  Reboot test: after `sudo reboot`, rules auto-load (`systemctl status nftables` is active; `nft list ruleset` shows the same).