# Networking (Part 2): NAT / DNAT / netns / UFW Deep

---

**Date:** 2025-09-18

**Topic:** ip netns, veth pairs, IPv4 forwarding, iptables NAT/DNAT, UFW (numbered rules)

---

## Goals

- Bring up an **isolated host** in `ip netns` and give it Internet via **NAT (MASQUERADE)**.
- Expose a **service from the namespace** to the host with **DNAT** (e.g., `8080 → 10.10.0.2:8080`).
- Manage **UFW** with numbered rules (insert/delete, logging), without locking yourself out.
- Verify flows with **tcpdump** and keep **cleanup** scripts handy.

---

## Security Checklist

- **Before enabling UFW over SSH**, whitelist your SSH port explicitly (`ufw allow 22/tcp` or your port).
- Scope DNAT to the **right ingress interface** if needed (match `i "$IF"` on PREROUTING/INPUT when exposing externally).
- Turn on UFW logging for audit trails: `sudo ufw logging on` (check with `journalctl -u ufw`).
- Avoid overly broad NAT sources (`s 10.0.0.0/8`); target your actual lab subnet.
- Verify **FORWARD policy** and allow rules; DNAT without FORWARD ACCEPT won’t pass traffic.

---

## Pitfalls

- Forgot `ip_forward` → namespace can’t reach the Internet.
- Wrong `o "$IF"` in MASQUERADE → NAT silently fails.
- **nftables vs iptables**: don’t mix stacks.
- UFW rule **order matters**: `insert` to place allows above denies.

---

## Practice

### 1) Create a network namespace

```bash
mkdir -p ~/labs/day10/captures
sudo ip netns add lab10Practice
1) Create a network namespace

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
```

Gives the network namespace end `10.10.0.2/24` and brings it up. Host and network namespace now share `10.10.0.0/24`.

---

### 6) Default route inside the **network namespace**

```bash
sudo ip -n lab10 route add default via 10.10.0.1
```

Sends all non-local traffic from the network namespace to the host (our gateway).

---

### 7) Enable IP forwarding

```bash
sudo sysctl -w net.ipv4.ip_forward=1
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
sudo iptables -t nat -C POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE 2>/dev/null || sudo iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE
```

Masquerades packets from `10.10.0.0/24` out via `$IF`. The network namespace now has internet via the host.

---

### 10) FORWARD veth0

```bash
sudo iptables -C FORWARD -i veth0 -o "$IF" -s 10.10.0.0/24 -j ACCEPT 2>/dev/null || sudo iptables -A FORWARD -i veth0 -o "$IF" -s 10.10.0.0/24 -j ACCEPT
sudo iptables -C FORWARD -i "$IF" -o veth0 -d 10.10.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || sudo iptables -A FORWARD -i "$IF" -o veth0 -d 10.10.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT
```

---

### 11) Port-forward host:8080 → ns:8080

```bash
sudo iptables -t nat -C PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null || sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080
```

DNAT: traffic hitting the host on TCP 8080 is redirected to `10.10.0.2:8080`.

```bash
sudo iptables -C FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT 2>/dev/null || sudo iptables -A FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT
```

Allows the forwarded flow; without this, the DNAT traffic would be dropped by FORWARD chain policy.

```bash
sudo iptables -t nat -C OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null || sudo iptables -t nat -A OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080
```

Local connections from the host (curl http://127.0.0.1:8080) - OUTPUT chain required

---

### 12) UFW

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 8080/tcp
sudo ufw enable
sudo ufw status numbered
```

---

### 13) Let's check from ns internet

```bash
sudo ip netns exec lab10 bash -c 'printf "ns IPs: "; ip -4 addr show veth1 | awk "/inet /{print \$2}"; ping -c1 -W1 1.1.1.1 && echo OK || echo FAIL'
```

---

### 14) Quick packet capture

```bash

# IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
# [ -n "$IF" ] || { echo "Не смог определить WAN интерфейс"; ip -o -4 route show; exit 1; }

sudo timeout 10 tcpdump -i "$IF" -nn -w ~/labs/day10/captures/https_$(date +%H%M%S).pcap 'tcp port 443'
```

Sniffs TCP/443 on `$IF` for 10 seconds and saves to `https.pcap` (open in Wireshark to prove traffic).

---

### 15) Cleanup

```bash
# remove rules (if added "-A", just add "-D" with the same parameters)
sudo iptables -t nat -D PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null || true
sudo iptables -t nat -D OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null || true
sudo iptables -D FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i veth0 -o "$IF" -s 10.10.0.0/24 -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i "$IF" -o veth0 -d 10.10.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
sudo iptables -t nat -D POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE 2>/dev/null || true

sudo ip netns del lab10 2>/dev/null || true
sudo ip link del veth0 2>/dev/null || true
```

---