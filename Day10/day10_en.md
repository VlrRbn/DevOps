# day10_en

# Networking (Part 2): NAT / DNAT / netns / UFW Deep

---

**Date:** **2025-09-18**

**Topic:** ip netns, veth pairs, IPv4 forwarding, iptables NAT/DNAT, UFW (numbered rules)

---

## Goals

- Bring up an **isolated host** in `ip netns` and give it Internet via **NAT (MASQUERADE)**.
- Expose a **service from the namespace** to the host with **DNAT** (e.g., `8080 → 10.10.0.2:8080`).
- Manage **UFW** with numbered rules (insert/delete, logging), without locking yourself out.
- Verify flows with **tcpdump** and keep **cleanup** scripts handy.

---

## Practice

### 1) Create a network namespace

```bash
mkdir -p ~/labs/day10/{captures,netns}
sudo ip netns del lab10 2>/dev/null || true
sudo ip netns add lab10
```

Makes an isolated network stack called `lab10` (its own interfaces, routes, iptables).

---

### 2) Make a virtual Ethernet cable

```bash
sudo ip link add veth0 type veth peer name veth1
```

Creates a veth pair (`veth0` ↔ `veth1`). Packets entering one end pop out the other.

---

### 3) Move one end into the namespace

```bash
sudo ip link set veth1 netns lab10
```

Puts `veth1` inside `lab10`. That’s the ns “NIC” connected to the host via `veth0`.

---

### 4) Host-side IP and up

```bash
sudo ip addr add 10.10.0.1/24 dev veth0
sudo ip link set veth0 up
```

Assigns `10.10.0.1/24` to the host end. This will be the ns default gateway.

---

### 5) Namespace IP and up

```bash
sudo ip -n lab10 addr add 10.10.0.2/24 dev veth1
sudo ip -n lab10 link set veth1 up
sudo ip -n lab10 link set lo up
```

Gives the network namespace end `10.10.0.2/24` and brings it up. Host and network namespace now share `10.10.0.0/24`.

---

### 6) Default route inside the **network namespace**

```bash
sudo ip -n lab10 route add default via 10.10.0.1
sudo ip netns exec lab10 ping -c 1 10.10.0.1
```

Sends all non-local traffic from the network namespace to the host (our gateway).

---

### 7) Enable IP forwarding

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.veth0.route_localnet=1
```

---

### 8) Detect the outbound (WAN) interface

```bash
IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
[ -n "$IF" ] || { echo "Unable to detect WAN interface"; ip -o -4 route show; exit 1; }
```

Finds the interface used for the default route (e.g., `eth0`, `wlan0`, `enp3s0`).

---

### 9) NAT from the ns to the internet

```bash
sudo iptables -t nat -C POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE 2>/dev/null \
|| sudo iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE

# DNS for the ns (quick):
sudo ip netns exec lab10 bash -lc 'echo nameserver 1.1.1.1 >/etc/resolv.conf'

# Test Internet:
sudo ip netns exec lab10 curl -sS https://ifconfig.io | head -1
```

Masquerades packets from `10.10.0.0/24` out via `$IF`. The network namespace now has internet via the host.

---

### 10) HTTP server inside ns

```bash
sudo ip netns exec lab10 bash -lc 'command -v python3 >/dev/null && (python3 -m http.server 8080 --bind 10.10.0.2 >/dev/null 2>&1 & echo $! >/tmp/http.pid) || true'
```

### 11) FORWARD veth0

```bash
sudo iptables -C FORWARD -i veth0 -o "$IF" -s 10.10.0.0/24 -j ACCEPT 2>/dev/null \
|| sudo iptables -A FORWARD -i veth0 -o "$IF" -s 10.10.0.0/24 -j ACCEPT

sudo iptables -C FORWARD -i "$IF" -o veth0 -d 10.10.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
|| sudo iptables -A FORWARD -i "$IF" -o veth0 -d 10.10.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT
```

---

### 12) Port-forward host:8080 → ns:8080

```bash
sudo iptables -t nat -C PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null \
|| sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080
```

DNAT: traffic hitting the host on TCP 8080 is redirected to `10.10.0.2:8080`.

```bash
sudo iptables -C FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT 2>/dev/null \
|| sudo iptables -A FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT
```

Allows the forwarded flow; without this, the DNAT traffic would be dropped by FORWARD chain policy.

```bash
sudo iptables -t nat -C OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null \
|| sudo iptables -t nat -A OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080
```

Local connections from the host (curl http://127.0.0.1:8080) - OUTPUT chain required

### 13) SNAT for hairpin

```bash
sudo iptables -t nat -C POSTROUTING -o veth0 -p tcp -d 10.10.0.2 --dport 8080 \
  -j SNAT --to-source 10.10.0.1 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -o veth0 -p tcp -d 10.10.0.2 --dport 8080 \
  -j SNAT --to-source 10.10.0.1
  
curl -sI http://127.0.0.1:8080 | head -5
```

---

### 14) UFW

```bash
sudo ufw status verbose || true
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 8080/tcp
sudo ufw allow in  on lo
sudo ufw allow out on lo
sudo ufw enable
sudo ufw status numbered
```

---

### 15) Let's check from ns internet

```bash
sudo ip netns exec lab10 bash -c 'printf "ns IPs: "; ip -4 addr show veth1 | awk "/inet /{print \$2}"; ping -c1 -W1 1.1.1.1 && echo OK || echo FAIL'
```

---

### 16) Quick packet capture

```bash

# IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
# [ -n "$IF" ] || { echo "Не смог определить WAN интерфейс"; ip -o -4 route show; exit 1; }

sudo timeout 10 tcpdump -i "$IF" -nn -w ~/labs/day10/captures/https_$(date +%H%M%S).pcap 'tcp port 443'
```

Sniffs TCP/443 on `$IF` for 10 seconds and saves to `https.pcap` (open in Wireshark to prove traffic).

---

### 17) Cleanup

```bash
# remove rules (if added "-A", just add "-D" with the same parameters)
sudo iptables -t nat -D PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null || true
sudo iptables -t nat -D OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null || true
sudo iptables -D FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i veth0 -o "$IF" -s 10.10.0.0/24 -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i "$IF" -o veth0 -d 10.10.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
sudo iptables -t nat -D POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE 2>/dev/null || true
sudo iptables -t nat -D POSTROUTING -o veth0 -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1 2>/dev/null

sudo ip netns del lab10 2>/dev/null || true
sudo ip link del veth0 2>/dev/null || true
ip netns list
ip link show | grep veth
sudo ufw status numbered     # sudo ufw delete 10,9,5,4
```

---

## Security Checklist

- **Before enabling UFW over SSH**, whitelist your SSH port explicitly (`ufw allow 22/tcp` or your port).
- Scope DNAT to the **right ingress interface** if needed (match `-i "$IF"` on PREROUTING/INPUT when exposing externally).
- Turn on UFW logging for audit trails: `sudo ufw logging on` (check with `journalctl -u ufw`).
- Avoid overly broad NAT sources (`-s 10.0.0.0/8`); target your actual lab subnet.
- Verify **FORWARD policy** and allow rules; DNAT without FORWARD ACCEPT won’t pass traffic.

---

## Pitfalls

- Forgot `ip_forward` → namespace can’t reach the Internet.
- Wrong `-o "$IF"` in MASQUERADE → NAT silently fails.
- **nftables vs iptables**: don’t mix stacks.
- UFW rule **order matters**: `insert` to place allows above denies.

---

## Labs

### `labs/day10/netns/netns-lab10.v2.sh`

```bash
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
```

## Notes

- Inside ns: `ping -c1 1.1.1.1` works and DNS resolves (temporary resolv.conf OK).
- `curl -ss https://ifconfig.io` inside ns shows the **host’s external IP** (NAT works).
- `ufw status numbered` shows `allow 8080/tcp` above default deny, logging enabled if desired.

---

## Summary
- Built an isolated ns (`lab10`) with veth pair and default route via host.
- Enabled IPv4 forwarding, added MASQUERADE for `10.10.0.0/24` out via `$IF`.
- Exposed ns:8080 with DNAT (PREROUTING for external, OUTPUT for localhost).
- Verified flows with `curl` and `tcpdump`, kept cleanup idempotent.

---

## Artifacts

- `labs/day10/netns/netns-lab10.v1.sh`
- `labs/day10/netns/netns-lab10.v2.sh`
- `labs/day10/captures/*.pcap`.

---

## To repeat
- Rebuild ns from scratch.
- Verify NAT counters again after one request.
- (Optional) Try hairpin via `$HOST_IP:8080`.

---

## Acceptance Criteria (self-check)

- [ ] Inside ns: `ping -c1 1.1.1.1` OK and `curl -s https://ifconfig.io` shows the host’s public IP (NAT works).
- [ ] From host: `curl -I http://127.0.0.1:8080` hits the Python server inside the ns (DNAT OUTPUT works).
- [ ] `iptables -t nat -L -v -n --line-numbers` shows counters increasing for `PREROUTING` 8080, `POSTROUTING` MASQUERADE; `FORWARD` ACCEPT for `10.10.0.2:8080` also grows.
- [ ] `ufw status numbered` — allow 8080/tcp is above any deny; logging is on if desired.