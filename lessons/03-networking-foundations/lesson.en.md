# lesson_03

# Networking Foundations: IP, DNS, Routes, and Diagnostics

**Date:** 2025-08-21  
**Topic:** IP addressing, DNS, routing, and basic network diagnostics  
**Daily goal:** Understand core networking concepts and run a minimal, practical connectivity troubleshooting flow.
**Bridge:** [00 Foundations Bridge](../00-foundations-bridge/00-foundations-bridge.md) for missing basics after lessons 1-4.

---

## 1. Core Networking Concepts

### IP address

An IP address identifies a host on a network.

- **IPv4** example: `192.168.1.12`
- **IPv6** example: `2001:db8:1::12`

A host can have multiple addresses on one interface.

### Private vs public addressing

- **Private IPv4 ranges** (not routed directly on the public internet):
  - `10.0.0.0/8`
  - `172.16.0.0/12`
  - `192.168.0.0/16`
- **Public IPv4**: globally routable addresses.

### DNS - Domain Name System

DNS translates names (for example `google.com`) into IP addresses.

Resolution order (simplified):

1. Local sources (`/etc/hosts`)
2. Configured DNS resolver
3. DNS servers

### Routing and default gateway

Routing decides where packets go.

- Same subnet: send directly.
- Outside subnet: send to default gateway.

---

## 2. Command Priority (What to Learn First)

### Core (must know now)

- `ip -br addr`
- `ip route`
- `ping -c 4 1.1.1.1`
- `ping -c 4 google.com`
- `traceroute -n 1.1.1.1`
- `dig +short google.com` **or** `nslookup google.com`

### Optional (useful after core)

- `ip link`
- `resolvectl status`
- `curl -I https://example.com`
- `wget --spider https://example.com`
- temporary `/etc/hosts` override for testing

### Advanced (later)

- `dig google.com A/AAAA/NS/MX`
- `dig +trace google.com`
- `mtr -rw -c 10 1.1.1.1`

---

## 3. Core Commands: Why and When

### `ip -br addr`

- **What it shows:** interface names, state, and IP addresses.
- **Why it matters:** first check when network is "not working".
- **Use when:** you need to confirm host has IP on active interface.

```bash
leprecha@Ubuntu-DevOps:~$ ip -br addr
lo               UNKNOWN        127.0.0.1/8 ::1/128
wlo1             UP             192.168.1.12/24 2001:db8:1::12/64 fe80::e02:7af1:917b:6b02/64
```

### `ip route`

- **What it shows:** routing table and default gateway.
- **Why it matters:** no default route -> internet usually unavailable.
- **Use when:** ping to internet IP fails.

```bash
leprecha@Ubuntu-DevOps:~$ ip route
default via 192.168.1.254 dev wlo1 proto dhcp src 192.168.1.12 metric 600
192.168.1.0/24 dev wlo1 proto kernel scope link src 192.168.1.12 metric 600
```

### `ping`

- **What it shows:** reachability and latency.
- **Why it matters:** separates “network down” from “DNS issue”.
- **Use when:** first connectivity test.

```bash
leprecha@Ubuntu-DevOps:~$ ping -c 4 1.1.1.1
leprecha@Ubuntu-DevOps:~$ ping -c 4 google.com
```

Interpretation:

- IP ping works, domain ping fails -> likely DNS issue.
- Both fail -> link/route/firewall issue.

### `traceroute -n`

- **What it shows:** path (hops) to destination.
- **Why it matters:** helps locate where traffic stops.
- **Use when:** ping fails or latency is unstable.

```bash
leprecha@Ubuntu-DevOps:~$ traceroute -n 1.1.1.1
traceroute to 1.1.1.1 (1.1.1.1), 30 hops max, 60 byte packets
 1  192.168.1.254  4.4 ms  4.2 ms  4.1 ms
 2  95.44.248.1    6.6 ms  6.8 ms  7.0 ms
 3  1.1.1.1        8.9 ms  9.1 ms  9.0 ms
```

`* * *` on some hops can be normal (filtering/rate-limit).

### `dig +short` or `nslookup`

- **What it shows:** DNS answer (domain -> IP).
- **Why it matters:** proves whether name resolution works.
- **Use when:** domain does not open, but internet may still work.

```bash
leprecha@Ubuntu-DevOps:~$ dig +short google.com
leprecha@Ubuntu-DevOps:~$ nslookup google.com
```

Rule of thumb:

- `dig` -> better for diagnostics/scripts.
- `nslookup` -> quick human-readable check.

---

## 4. Optional Commands (After Core)

These commands are not required for first-pass troubleshooting, but they make your diagnostics more accurate.

### `ip link`

- **What it shows:** low-level interface details (state, MAC, MTU, flags).
- **Why it matters:** helps when interface exists but behaves oddly.
- **Use when:** interface is visible in `ip -br addr`, but traffic still fails.

```bash
leprecha@Ubuntu-DevOps:~$ ip link
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: wlo1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP mode DORMANT group default qlen 1000
    link/ether e4:2d:56:e5:3f:14 brd ff:ff:ff:ff:ff:ff
```

### `resolvectl status`

- **What it shows:** active DNS resolver, DNS servers, and per-link DNS scopes.
- **Why it matters:** you see which DNS server is actually used right now.
- **Use when:** DNS resolves inconsistently across networks.

```bash
leprecha@Ubuntu-DevOps:~$ resolvectl status
Global
       Protocols: -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
resolv.conf mode: stub

Link 3 (wlo1)
    Current Scopes: DNS
         Protocols: +DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
Current DNS Server: 192.168.1.254
       DNS Servers: 192.168.1.254 2001:4860:4860::8888
```

### `curl -I`

- **What it shows:** only HTTP response headers (status, redirects, content type).
- **Why it matters:** proves app-layer connectivity, not just ICMP reachability.
- **Use when:** ping works, but browser behavior is unclear.

```bash
leprecha@Ubuntu-DevOps:~$ curl -I https://google.com
HTTP/2 301
location: https://www.google.com/
content-type: text/html; charset=UTF-8
```

### `wget --spider`

- **What it shows:** URL availability without downloading payload.
- **Why it matters:** fast check for automation and endpoint monitoring.
- **Use when:** you need simple up/down check for a URL.

```bash
leprecha@Ubuntu-DevOps:~$ wget --spider https://example.com
Spider mode enabled. Check if remote file exists.
HTTP request sent, awaiting response... 200 OK
Remote file exists.
```

### `/etc/hosts` local override (temporary)

- **What it does:** forces local hostname resolution to chosen IP.
- **Why it matters:** useful for pre-DNS testing or local environment mapping.
- **Use when:** you want local test mapping before real DNS record exists.

Add mapping:

```bash
echo "1.2.3.4 mytest.local" | sudo tee -a /etc/hosts
```

Verify mapping:

```bash
getent hosts mytest.local
```

Remove mapping (manual, beginner-safe):

```bash
sudo nano /etc/hosts
# remove the mytest.local line, save, exit
```

---

## 5. Advanced Commands (Deeper Diagnostics)

### `dig` record-focused queries

- **What it shows:** full DNS answers with record type, TTL, and server details.
- **Why it matters:** lets you diagnose DNS by record type, not only name->IP.
- **Use when:** service works for one feature but fails for another (web, mail, etc.).

```bash
leprecha@Ubuntu-DevOps:~$ dig google.com A
leprecha@Ubuntu-DevOps:~$ dig google.com AAAA
leprecha@Ubuntu-DevOps:~$ dig google.com NS
leprecha@Ubuntu-DevOps:~$ dig google.com MX
leprecha@Ubuntu-DevOps:~$ dig +short google.com
```

### Query specific DNS server with `dig @server`

- **What it shows:** answer from selected resolver (not your default one).
- **Why it matters:** compare DNS propagation and resolver differences.
- **Use when:** one DNS server resolves, another does not.

```bash
leprecha@Ubuntu-DevOps:~$ dig @1.1.1.1 google.com A
leprecha@Ubuntu-DevOps:~$ dig @8.8.8.8 google.com A
```

### `dig +trace`

- **What it shows:** full DNS delegation path from root to authoritative servers.
- **Why it matters:** helps find where resolution chain breaks.
- **Use when:** normal `dig` fails or returns unexpected answer.

```bash
leprecha@Ubuntu-DevOps:~$ dig +trace google.com
```

### `mtr`

- **What it shows:** live hop-by-hop packet loss and latency statistics.
- **Why it matters:** better than one-shot traceroute for unstable links.
- **Use when:** intermittent latency spikes or random packet loss.

```bash
leprecha@Ubuntu-DevOps:~$ mtr -rw -c 10 1.1.1.1
```

---

## 6. Minimal Practice (Core Path)

### Goal

Run the smallest useful troubleshooting flow without overload.

### Steps

1. Save local network state.
2. Check connectivity to IP and domain.
3. Check route path.
4. Check DNS resolution.

```bash
mkdir -p ~/net-lab

ip -br addr > ~/net-lab/ip_addr.txt
ip route > ~/net-lab/ip_route.txt

ping -c 4 1.1.1.1
ping -c 4 google.com
traceroute -n 1.1.1.1

dig +short google.com
# alternative:
# nslookup google.com
```

Validation checklist:

- `~/net-lab/ip_addr.txt` exists
- `~/net-lab/ip_route.txt` exists
- At least one DNS command returns IPs

---

## 7. Extended Practice (Optional + Advanced)

1. Save resolver status:

```bash
resolvectl status > ~/net-lab/dns_status.txt
```

2. Check web response headers:

```bash
curl -I https://google.com
wget --spider https://example.com
```

3. Test local hosts override:

```bash
echo "1.2.3.4 mytest.local" | sudo tee -a /etc/hosts
getent hosts mytest.local
sudo nano /etc/hosts
```

4. Run deeper DNS checks:

```bash
dig google.com A
dig google.com NS
dig google.com MX
dig @1.1.1.1 google.com A
dig +trace google.com
```

5. Collect path quality snapshot:

```bash
mtr -rw -c 10 1.1.1.1 > ~/net-lab/mtr_1_1_1_1.txt
```

---

## 8. Lesson Summary

- **What I learned:** IP basics, private/public addressing, DNS resolution flow, and default gateway routing.
- **What I practiced:** core diagnostics (`ip`, `ping`, `traceroute`, DNS check) plus optional and advanced tools for deeper analysis.
- **Core idea:** first verify link and route, then DNS, then app-layer behavior and resolver path.
- **Needs repetition:** reading resolver output, comparing DNS record types, and interpreting `mtr` loss/latency patterns.
- **Next step:** create a script with two modes: `core-check` and `deep-check`.
