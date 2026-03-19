# 08-11 Networking + Text Bridge (After Lessons 8-11)

**Purpose:** close all practical gaps between text processing, network diagnostics, NAT/DNAT, and `nftables` persistence.

This bridge does not replace lessons 8-11.
Use it as an operational reference when handling real incidents, not just replaying commands.

---

## 0. How to use this file

Working order:

1. Start from a symptom.
2. Jump to the relevant section (08/09/10/11).
3. Run the minimal checklist.
4. Save evidence (log, pcap, ruleset dump).
5. Cleanup and document findings.

Core rule: **source of truth = observable facts** (counters, trace, pcap, status).

---

## 1. Unified troubleshooting model (for 8-11)

Validation chain:

1. `input` (what exactly fails: DNS, HTTP, port, route).
2. `state` (interfaces, addresses, routes, sockets, policy).
3. `path` (expected packet path through hooks/chains).
4. `proof` (counter/trace/pcap/log).
5. `rollback` (how to safely revert).

Practical command baseline:

```bash
# 1) Network state
ip -br a
ip route
ss -tulpn

# 2) DNS + app
getent hosts example.com || true
curl -sS --max-time 5 https://example.com >/dev/null || true

# 3) Firewall/NAT state
sudo iptables -L -v -n
sudo iptables -t nat -L -v -n
sudo nft list ruleset
```

---

## 2. Lesson 08 Bridge: `grep` / `sed` / `awk`

### 2.1 `grep`: three modes you use most

```bash
# 1) Pattern + line numbers
grep -nE 'error|failed|timeout' app.log

# 2) Invert match (remove noise)
grep -vE '^$|^#' config.conf

# 3) Recursive search
grep -R --line-number --color=never 'PermitRootLogin' /etc/ssh 2>/dev/null
```

Use cases:

- log triage;
- config parameter lookup;
- pre-check before `sed` edits.

### 2.2 `sed`: safe editing pattern

```bash
# preview first
sed -n '1,120p' file.conf

# edit with backup
sed -ri.bak 's/^#?PermitRootLogin .*/PermitRootLogin no/' file.conf

# verify
grep -n '^PermitRootLogin' file.conf
```

Rule: in training and production, avoid direct edits without backup.

### 2.3 `awk`: when `grep` is no longer enough

Examples:

```bash
# 1) Top IP frequency from access log
awk '{print $1}' access.log | sort | uniq -c | sort -nr | head

# 2) HTTP status distribution
awk '{print $9}' access.log | sort | uniq -c | sort -nr

# 3) Filter 5xx lines
awk '$9 ~ /^5/ {print $1, $7, $9}' access.log | head
```

If you need grouping/counting, this is usually `awk` territory.

### 2.4 Pipeline-debug (why pipeline "fails")

Always split by stage:

```bash
# A
journalctl -u ssh -o cat -n 50

# A|B
journalctl -u ssh -o cat -n 50 | grep -E 'Failed|Accepted'

# A|B|C
journalctl -u ssh -o cat -n 50 | grep -E 'Failed|Accepted' | awk '{print $1, $2, $3, $0}'
```

---

## 3. Lesson 09 Bridge: network diagnostics from socket to packet

### 3.1 Minimal checklist: "service is unavailable"

```bash
# interface/address/route
ip -br a
ip route

# listener state
ss -tulpn | grep -E ':80|:443|:8080|:22' || true

# DNS
dig +short example.com

# policy
sudo ufw status verbose || true

# packet proof
IF="$(ip -o route show to default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo timeout 8 tcpdump -i "$IF" -nn 'tcp port 443'
```

### 3.2 `tcpdump`: why captures can be empty

Common causes:

- wrong interface;
- local (`localhost`) traffic not visible on external IF;
- filter too narrow.

Fallback:

```bash
sudo timeout 8 tcpdump -i any -nn 'tcp port 8080'
```

### 3.3 DNS vs transport

If `curl` reports `Resolving timed out`:

- this is not automatically "no internet";
- often DNS-path (UDP/TCP 53) or resolver issue.

Split checks:

```bash
dig +short example.com
curl -sS --max-time 5 https://1.1.1.1 >/dev/null || true
```

---

## 4. Lesson 10 Bridge: NAT/DNAT with `iptables`

### 4.1 Three different flows

1. Namespace -> internet (egress):

```text
ns -> veth -> FORWARD -> nat/POSTROUTING(MASQUERADE) -> WAN
```

2. External -> host:8080 -> namespace:

```text
client -> nat/PREROUTING(DNAT) -> FORWARD -> ns
```

3. Host localhost -> namespace (hairpin):

```text
host -> nat/OUTPUT(DNAT) -> nat/POSTROUTING(SNAT) -> ns
```

### 4.2 Why "NAT exists but traffic still fails"

Because NAT does not replace filter policy.
If `FORWARD=DROP`, you still need explicit allow rules.

Diagnostics:

```bash
sudo iptables -S FORWARD
sudo iptables -L FORWARD -v -n
```

### 4.3 Idempotent apply pattern

```bash
sudo iptables -C FORWARD ... 2>/dev/null || sudo iptables -A FORWARD ...
```

Why:

- rerunnable setup without duplicate rules;
- deterministic automation.

### 4.4 Counter reading

```bash
sudo iptables -t nat -L -v -n --line-numbers
sudo iptables -L FORWARD -v -n --line-numbers
```

Take baseline -> run 1-2 requests -> read again -> compare expected rule growth.

---

## 5. Lesson 11 Bridge: `nftables` NAT/DNAT + trace + persistence

### 5.1 `nft` structure model

- `table` -> logical scope;
- `chain` -> ordered rules;
- `hook` -> path point;
- `counter` -> match proof.

### 5.2 Runtime and ruleset file workflow

Operational pattern:

1. build file (`/tmp/lesson11.nft`);
2. `sudo nft -f /tmp/lesson11.nft`;
3. verify with `sudo nft list table ip nat`.

### 5.3 Why `nft monitor trace` can be silent

Trace output appears only when packet has `nftrace` flag.

Minimal flow:

```bash
# terminal A
sudo nft monitor trace

# terminal B
./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh --trace-once
```

`--trace-once` temporarily injects `meta nftrace set 1`, runs one request, then removes it.

### 5.4 `FORWARD=DROP` caveat (Docker/UFW hosts)

Even with valid `nft` NAT, egress may fail without `iptables FORWARD` allow rules.
Current `setup-nft-netns.sh` already automates those rules.

### 5.5 Persistence + rollback

Minimal safe flow:

```bash
sudo cp -a /etc/nftables.conf /etc/nftables.conf.bak.$(date +%F_%H%M%S)
sudo nft -c -f /etc/nftables.conf
sudo nft -f /etc/nftables.conf
sudo systemctl enable --now nftables
```

Rollback:

```bash
# sudo cp /etc/nftables.conf.bak.YYYY-MM-DD_HHMMSS /etc/nftables.conf
# sudo nft -c -f /etc/nftables.conf
# sudo systemctl restart nftables
```

---

## 6. ICMP vs TCP egress (critical practical point)

If `ping 1.1.1.1` fails, NAT may still be healthy.

Typical reasons:

- upstream blocks ICMP;
- policy allows TCP but drops ICMP;
- DNS is broken separately from transport.

TCP egress check:

```bash
sudo ip netns exec lab11 curl -sS --max-time 5 https://ifconfig.io/ip
```

"Egress OK" criteria:

- either successful `ping`,
- or successful TCP check (`curl`).

---

## 7. Symptom -> check -> action

### 7.1 Namespace has no external egress

Check:

```bash
ip netns exec lab11 ip route
sudo sysctl net.ipv4.ip_forward
sudo iptables -S FORWARD
sudo nft list table ip nat
```

Action:

- enable `ip_forward`;
- ensure FORWARD allow rules;
- confirm `masquerade` counter increments.

### 7.2 `nft monitor trace` has no output

Check:

```bash
sudo nft -a list chain ip nat output
```

Action:

- use `--trace-once`;
- or add temporary manual `meta nftrace set 1` rule.

### 7.3 `tcpdump` sees nothing

Check:

- interface selection;
- traffic generated within capture window;
- filter width.

Action:

- fallback to `-i any`;
- increase timeout;
- generate traffic explicitly.

---

## 8. Quick command shortlist

```bash
# text
grep -nE 'error|failed|timeout' app.log
sed -n '1,120p' file.conf
awk '{print $1}' access.log | sort | uniq -c | sort -nr | head

# network state
ip -br a
ip route
ss -tulpn

# firewall/nat
sudo iptables -L FORWARD -v -n
sudo iptables -t nat -L -v -n
sudo nft list table ip nat

# trace + packet
sudo nft monitor trace
sudo timeout 8 tcpdump -i any -nn 'tcp port 8080'

# lesson11 helpers
./lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh
./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh --trace-once
./lessons/11-nftables-nat-dnat-persistence/scripts/cleanup-nft-netns.sh
```

---

## 9. Responsibility boundaries

- Lesson 08: text/log processing.
- Lesson 09: network path and policy diagnostics.
- Lesson 10: `iptables` NAT/DNAT, netns, hairpin.
- Lesson 11: `nftables` NAT/DNAT, trace, persistence.
