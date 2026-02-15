# lesson_10

# Networking (Part 2): NAT / DNAT / `netns` / UFW

**Date:** 2025-09-18  
**Topic:** `ip netns`, `veth`, IPv4 forwarding, `iptables` NAT/DNAT, and safe UFW operations.  
**Daily goal:** Build an isolated namespace network, provide internet via NAT, publish namespace service via DNAT, and clean everything safely.
**Bridge:** [08-11 Networking + Text Bridge](../00-foundations-bridge/08-11-networking-text-bridge.md) for deep explanations and troubleshooting across lessons 8-11.
**Legacy:** original old notes remain in `lessons/10-networking-nat-dnat-netns-ufw/lesson_10(legacy).md`.

---

## 0. Prerequisites

Before starting, verify required tools exist:

```bash
command -v ip iptables sysctl curl python3
```

Optional (for pcap):

```bash
command -v tcpdump || echo "install tcpdump if needed"
```

---

## 1. Core Concepts

### 1.1 What this lesson solves

We build a local "host <-> namespace" lab and walk the full flow:

1. L3 connectivity inside lab subnet;
2. namespace internet access (NAT/MASQUERADE);
3. service exposure through host port (DNAT);
4. packet/counter verification;
5. safe cleanup.

### 1.2 NAT vs DNAT

- `SNAT/MASQUERADE`: rewrites source address on outbound traffic (namespace -> WAN).
- `DNAT`: rewrites destination address on inbound traffic (host:8080 -> ns:8080).

### 1.3 Why `ip_forward` is required

Without `net.ipv4.ip_forward=1`, host will not route packets between interfaces, so namespace cannot reach external networks through host.

### 1.4 FORWARD chain is mandatory

Even with NAT configured, traffic can still be dropped if `FORWARD` does not explicitly allow required paths.

### 1.5 Hairpin (localhost DNAT)

To make `curl http://127.0.0.1:8080` on host reach namespace service, you typically need `OUTPUT` DNAT and `POSTROUTING` SNAT on `veth0`.

### 1.6 UFW and remote safety

UFW is useful for policy control but risky on remote hosts without rollback. Allow SSH first, enable second.

### 1.7 Verification must be factual

Success criteria should be measurable:

- ping/curl from namespace;
- `curl` to host localhost port;
- increased counters in `iptables -L -v`.

---

## 2. Command Priority (What to Learn First)

### Core (must know now)

- `ip netns add|exec|del`
- `ip link add ... type veth peer ...`
- `ip -n <ns> addr|route|link`
- `sysctl net.ipv4.ip_forward=1`
- `iptables -t nat -A POSTROUTING ... MASQUERADE`
- `iptables -t nat -A PREROUTING ... DNAT`
- `iptables -L -v -n` / `iptables -t nat -L -v -n`

### Optional (after core)

- `ufw status numbered`
- `ufw default deny incoming` + explicit allow rules
- `tcpdump -i <if> -w <pcap> 'filter'`
- `curl -I` smoke checks

### Advanced (operations-grade)

- idempotent apply pattern (`-C || -A`)
- state file for deterministic cleanup
- restoring previous sysctl values after lab

---

## 3. Core Commands: What / Why / When

### `ip netns add lab10`

- **What:** creates isolated network namespace.
- **Why:** safe, reproducible lab without VMs.
- **When:** first step of lab setup.

```bash
sudo ip netns del lab10 2>/dev/null || true
sudo ip netns add lab10
```

### `ip link add veth0 type veth peer name veth1`

- **What:** creates virtual Ethernet cable between host and namespace.
- **Why:** links two network stacks.
- **When:** right after namespace creation.

```bash
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns lab10
```

### Addressing and default route

- **What:** assign host/ns addresses and default route inside namespace.
- **Why:** establish basic L3 connectivity.
- **When:** before NAT.

```bash
sudo ip addr add 10.10.0.1/24 dev veth0
sudo ip link set veth0 up

sudo ip -n lab10 addr add 10.10.0.2/24 dev veth1
sudo ip -n lab10 link set veth1 up
sudo ip -n lab10 link set lo up
sudo ip -n lab10 route add default via 10.10.0.1

sudo ip netns exec lab10 ping -c 1 10.10.0.1
```

### `sysctl` forwarding

- **What:** enable IPv4 forwarding and route_localnet for hairpin flow.
- **Why:** allow host to route between interfaces and localhost DNAT path.
- **When:** before NAT/DNAT rules.

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.veth0.route_localnet=1
```

### NAT (MASQUERADE)

- **What:** rewrite source of namespace subnet to host WAN interface.
- **Why:** provide outbound internet access from namespace.
- **When:** after routing is configured.

```bash
IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo iptables -t nat -C POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE 2>/dev/null || \
  sudo iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE
```

### DNAT (host:8080 -> ns:8080)

- **What:** forward host inbound traffic to namespace service.
- **Why:** expose namespace app via host endpoint.
- **When:** after service starts in namespace.

```bash
sudo iptables -t nat -C PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null || \
  sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080

sudo iptables -C FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT
```

Why commands look "repeated":

- this is the same idempotent pattern: `-C` (check) + `|| -A` (append);
- if a rule already exists, `-C` succeeds and `-A` is skipped;
- if a rule is missing, `-C` fails and `-A` adds it;
- this keeps setup re-runnable without duplicated rules.

---

## 4. Optional Commands (After Core)

### `OUTPUT` DNAT for localhost tests

```bash
sudo iptables -t nat -C OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080 2>/dev/null || \
  sudo iptables -t nat -A OUTPUT -p tcp --dport 8080 -d 127.0.0.1 -j DNAT --to-destination 10.10.0.2:8080
```

### Hairpin SNAT

```bash
sudo iptables -t nat -C POSTROUTING -o veth0 -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1 2>/dev/null || \
  sudo iptables -t nat -A POSTROUTING -o veth0 -p tcp -d 10.10.0.2 --dport 8080 -j SNAT --to-source 10.10.0.1
```

### UFW visibility

```bash
sudo ufw status verbose || true
sudo ufw status numbered || true
```

### Quick pcap

```bash
sudo timeout 10 tcpdump -i "$IF" -nn -w /tmp/lesson10_8080.pcap 'tcp port 8080'
```

### Practical Optional path

1. Validate baseline first: `curl -I http://127.0.0.1:8080`.
2. If only localhost path fails, add `OUTPUT` DNAT.
3. If localhost still fails, add hairpin `SNAT`.
4. Re-run `curl -I` and inspect NAT/FORWARD counters.
5. With UFW on remote hosts, prefer inspection (`status numbered`) and narrow allow rules only.

---

## 5. Advanced Topics (Ops-Grade)

### 5.1 Idempotent apply

Pattern `iptables -C ... || iptables -A ...` allows repeatable setup without duplicate rules.

### 5.2 State-driven cleanup

Store `NS`, `IF`, `SUBNET`, previous `sysctl` values into a state file so cleanup can safely revert exactly what was changed.

### 5.3 Policy-first workflow

Read current rules/policy/counters first, apply changes second, verify immediately after apply.

### 5.4 What to do in Advanced, step by step

1. Apply lab setup via script:
`./lessons/10-networking-nat-dnat-netns-ufw/scripts/setup-netns-nat.sh`
2. Validate connectivity and counters:
`./lessons/10-networking-nat-dnat-netns-ufw/scripts/check-netns-nat.sh`
3. Capture short pcap on target port and repeat requests.
4. Compare counters before/after (expect growth in MASQUERADE/DNAT/FORWARD).
5. Fully cleanup and restore sysctl:
`./lessons/10-networking-nat-dnat-netns-ufw/scripts/cleanup-netns-nat.sh`

### 5.5 Packet path map (what triggers where)

Internet access from namespace:

```text
lab10 (10.10.0.2) -> veth1 -> veth0(host) -> FORWARD -> nat/POSTROUTING(MASQUERADE) -> WAN(IF)
```

Inbound traffic to host:8080:

```text
client -> host:8080 -> nat/PREROUTING(DNAT to 10.10.0.2:8080) -> FORWARD -> veth0 -> lab10
```

Local host call to `127.0.0.1:8080`:

```text
host process -> nat/OUTPUT(DNAT) -> routing -> nat/POSTROUTING(SNAT hairpin) -> veth0 -> lab10
```

### 5.6 What `route_localnet=1` does and when needed

`net.ipv4.conf.veth0.route_localnet=1` enables special-case routing behavior for local 127/8 destinations in hairpin scenarios.  
Without it, localhost-DNAT often behaves inconsistently or fails.

Check:

```bash
sysctl net.ipv4.conf.veth0.route_localnet
```

### 5.7 Symptom-driven troubleshooting matrix

| Symptom | Where to inspect | Common cause | Action |
|---|---|---|---|
| `ns -> gateway` ping fails | `ip -n lab10 addr`, `ip link`, `ip route` | interface/address/route missing | verify `10.10.0.1/24`, `10.10.0.2/24`, `default via 10.10.0.1` |
| `ns -> internet` fails | `sysctl ip_forward`, nat `POSTROUTING`, `FORWARD` | missing forwarding/NAT/forward allow | enable `ip_forward`, add MASQUERADE and FORWARD accepts |
| `curl 127.0.0.1:8080` fails while ns service is up | nat `OUTPUT`, hairpin SNAT | missing OUTPUT DNAT or SNAT | add OUTPUT DNAT and SNAT on `veth0` |
| DNAT rule exists but no traffic | `FORWARD -v`, `nat -v`, `tcpdump` | wrong match on IF/port/address | verify interface/port, run short pcap |
| After reboot everything is gone | `iptables -S`, `sysctl` | rules were runtime-only | re-apply setup or use persistence mechanism |

### 5.8 How to read counters correctly

Workflow:

1. Capture baseline counters:
`sudo iptables -t nat -L -v -n --line-numbers`
2. Run 1-2 control requests (`curl`, `ping`).
3. Capture counters again.
4. Confirm growth in target rules (`DNAT`, `MASQUERADE`, `FORWARD ACCEPT`).

If counters do not grow:

- rule does not match interface/address/port;
- traffic takes a different path;
- packet is dropped earlier in chain flow.

### 5.9 `iptables` backend: legacy vs nft

On modern systems, `iptables` may run on top of nft backend.  
Issues appear when rules are modified through mixed stacks without clear backend awareness.

Check backend:

```bash
iptables --version
update-alternatives --display iptables 2>/dev/null || true
```

Practical lesson rule: keep one consistent stack per lab run.

### 5.10 What happens after reboot

In this lesson, rules and sysctl are runtime changes.  
After reboot, they may revert to system defaults.

### 5.11 DNAT safety baseline

Avoid overly broad forwarding "from anywhere to anywhere" unless required.

Constrain by:

- ingress interface (`-i "$IF"` where applicable);
- source network/address;
- exact port and protocol;
- short-lived rules removed after testing.

---

## 6. Scripts in This Lesson

### Manual Core flow (do once without script)

This block exists to understand mechanics first, then use automation.

```bash
# 1) netns + veth
sudo ip netns del lab10 2>/dev/null || true
sudo ip netns add lab10
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns lab10

# 2) addresses + route
sudo ip addr add 10.10.0.1/24 dev veth0
sudo ip link set veth0 up
sudo ip -n lab10 addr add 10.10.0.2/24 dev veth1
sudo ip -n lab10 link set veth1 up
sudo ip -n lab10 link set lo up
sudo ip -n lab10 route add default via 10.10.0.1

# 3) forwarding
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.veth0.route_localnet=1

# 4) NAT/DNAT
IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o "$IF" -j MASQUERADE
sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.10.0.2:8080
sudo iptables -A FORWARD -p tcp -d 10.10.0.2 --dport 8080 -j ACCEPT

# 5) service + checks
sudo ip netns exec lab10 bash -lc 'python3 -m http.server 8080 --bind 10.10.0.2 >/tmp/lab10_http.log 2>&1 &'
curl -sI http://127.0.0.1:8080 | head -n 5 || true
sudo iptables -t nat -L -v -n
```

After this, run `setup-netns-nat.sh` and compare: the script does the same flow but idempotently and with state-file driven cleanup.

Artifacts:

- `lessons/10-networking-nat-dnat-netns-ufw/scripts/`

Set execution bit:

```bash
chmod +x lessons/10-networking-nat-dnat-netns-ufw/scripts/*.sh
```

Help checks:

```bash
./lessons/10-networking-nat-dnat-netns-ufw/scripts/setup-netns-nat.sh --help
./lessons/10-networking-nat-dnat-netns-ufw/scripts/check-netns-nat.sh --help
./lessons/10-networking-nat-dnat-netns-ufw/scripts/cleanup-netns-nat.sh --help
```

---

## 7. Mini-lab (Core Path)

```bash
./lessons/10-networking-nat-dnat-netns-ufw/scripts/setup-netns-nat.sh

sudo ip netns exec lab10 ping -c 1 10.10.0.1
sudo ip netns exec lab10 ping -c 1 1.1.1.1
curl -sI http://127.0.0.1:8080 | head -n 5

sudo iptables -t nat -L -v -n --line-numbers | sed -n '1,80p'
sudo iptables -L FORWARD -v -n --line-numbers | sed -n '1,80p'
```

Checklist:

- namespace can ping gateway;
- namespace reaches outside network;
- localhost:8080 reaches namespace HTTP service;
- NAT/FORWARD counters increase.

---

## 8. Extended Lab (Optional + Advanced)

```bash
# DNS + external IP inside namespace
sudo ip netns exec lab10 bash -lc 'echo nameserver 1.1.1.1 >/etc/resolv.conf'
sudo ip netns exec lab10 curl -sS https://ifconfig.io | head -n 1

# UFW (only with rollback awareness)
sudo ufw status verbose || true
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 8080/tcp
sudo ufw enable
sudo ufw status numbered

# capture 8080
IF="$(ip -o -4 route show default table main | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo timeout 10 tcpdump -i "$IF" -nn -w /tmp/lesson10_8080.pcap 'tcp port 8080'
```

---

## 9. Cleanup

```bash
./lessons/10-networking-nat-dnat-netns-ufw/scripts/cleanup-netns-nat.sh
sudo ufw disable || true
rm -f /tmp/lesson10_8080.pcap
```

---

## 10. Lesson Summary

- **What I learned:** end-to-end lab flow `netns -> routing -> NAT -> DNAT -> verification`.
- **What I practiced:** namespace setup, port forwarding, counter-based validation, and deterministic cleanup.
- **Advanced skills:** idempotent iptables rule management and state-aware rollback.
- **Operational focus:** validate first, apply second, cleanup always; never leave temporary lab rules active unintentionally.
- **Repo artifacts:** `lessons/10-networking-nat-dnat-netns-ufw/scripts/`, `lessons/10-networking-nat-dnat-netns-ufw/scripts/README.md`.
