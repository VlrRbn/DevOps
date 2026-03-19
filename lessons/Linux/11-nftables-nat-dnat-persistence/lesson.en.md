# lesson_11

# Networking (Part 3): `nftables` NAT/DNAT + Persistence

**Date:** 2025-09-21  
**Topic:** `nftables` ruleset, NAT/DNAT/hairpin, counters/trace, and reboot persistence.  
**Daily goal:** Move from ad-hoc `iptables` rules to a clean `nftables` workflow with reliable debugging and controlled persistence.
**Bridge:** [08-11 Networking + Text Bridge](../00-foundations-bridge/08-11-networking-text-bridge.md) for deep explanations and troubleshooting across lessons 8-11.
**Legacy:** original notes remain in `lessons/11-nftables-nat-dnat-persistence/lesson_11(legacy).md`.

---

## 0. Prerequisites

Before starting, verify baseline dependencies:

```bash
command -v nft ip iptables sysctl curl python3
nft --version
```

Optional for pcap:

```bash
command -v tcpdump || echo "install tcpdump if needed"
```

---

## 1. Core Concepts

### 1.1 What changes compared to lesson 10

Lesson 10 used `iptables` for NAT/DNAT. Lesson 11 keeps same traffic goals but models them as one `nftables` ruleset:

- easier to read and maintain;
- easier to store and restore;
- better counter + trace visibility for debugging.

### 1.2 Table, chain, hook, priority

`nftables` model:

- `table` = logical rule group;
- `chain` = ordered rules bound to a specific hook;
- `hook` = packet path point (`prerouting`, `output`, `postrouting`);
- `priority` = evaluation order inside hook.

### 1.3 NAT flow in nft

- `prerouting`: DNAT for inbound traffic;
- `output`: DNAT for local host traffic (`127.0.0.1`/hairpin);
- `postrouting`: MASQUERADE/SNAT for outbound and reply path.

### 1.4 Counter-first troubleshooting

Using `counter` in rules gives proof packets hit the rule, not just that the rule exists.

### 1.5 `nft monitor trace`

Trace mode shows exact chain/rule matching in real time. It is the fastest way to locate packet drops/mismatches.

### 1.6 Persistence across reboot

Runtime rules disappear after reboot unless saved and loaded by `nftables.service`.

### 1.7 Safety and blast radius

For lab work, prefer updating/deleting only `table ip nat` instead of global `flush ruleset`, so you avoid breaking unrelated firewall state.

### 1.8 `FORWARD` policy caveat

`nft` NAT rules alone are not enough if host filter policy has `FORWARD=DROP` (common on Docker/UFW hosts).
In that case you also need explicit `iptables FORWARD` allow rules for `veth` <-> outbound interface traffic.

---

## 2. Command Priority (What to Learn First)

### Core (must know now)

- `nft list ruleset`
- `nft list table ip nat`
- `nft -f <file.nft>`
- `nft delete table ip nat`
- `sysctl net.ipv4.ip_forward=1`
- `ip netns ...` + `veth`
- `iptables -C/-A FORWARD ...` (for hosts with `FORWARD=DROP`)

### Optional (after core)

- `nft -a list ruleset` (handles)
- `nft monitor trace`
- `tcpdump` for packet proof
- `systemctl enable --now nftables`

### Advanced (ops-grade)

- ruleset design without stack mixing (`nft` vs `iptables`)
- persistence workflow: backup/validate/apply
- state-driven cleanup and rollback

---

## 3. Core Commands: What / Why / When

### `nft list ruleset`

- **What:** full active ruleset dump.
- **Why:** baseline understanding before/after changes.
- **When:** always around apply/debug cycles.

```bash
sudo nft list ruleset
```

### `nft -f /tmp/lesson11.nft`

- **What:** load rules from file.
- **Why:** deterministic and reviewable apply.
- **When:** after editing candidate ruleset.

```bash
sudo nft -f /tmp/lesson11.nft
```

### Where `/tmp/lesson11.nft` comes from

There are two valid paths:

1. **Via script** (recommended in this lesson):  
`./lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh`  
The script builds the ruleset, writes it to `/tmp/lesson11.nft`, then runs `sudo nft -f /tmp/lesson11.nft`.

2. **Manually** (to learn the mechanics):

```bash
IF="$(ip -o route show to default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
NS_IP="10.10.0.2"
PORT=8080

cat > /tmp/lesson11.nft <<EOF
table ip nat {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "$IF" tcp dport $PORT counter dnat to $NS_IP:$PORT
  }
  chain output {
    type nat hook output priority dstnat; policy accept;
    ip daddr 127.0.0.1 tcp dport $PORT counter dnat to $NS_IP:$PORT
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr $NS_IP tcp dport $PORT counter snat to 10.10.0.1
    ip saddr 10.10.0.0/24 oifname != "lo" counter masquerade
  }
}
EOF

sudo nft -f /tmp/lesson11.nft
sudo nft list table ip nat
```

Purpose of manual path: you can see how plain ruleset text becomes active nft rules, then use script automation for the same flow.

### `nft delete table ip nat`

- **What:** remove lesson NAT table only.
- **Why:** controlled cleanup without global firewall reset.
- **When:** restart lab or final cleanup.

```bash
sudo nft delete table ip nat 2>/dev/null || true
```

### `ip_forward` + `route_localnet`

- **What:** enable routing and localhost hairpin support.
- **Why:** required for namespace egress and local DNAT path.
- **When:** before connectivity tests.

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.veth0.route_localnet=1
```

---

## 4. Optional Commands (After Core)

The Optional block is about confidence in troubleshooting: not just "it failed", but exactly where and why.

### 4.1 `nft -a list ruleset`

- **What:** prints ruleset with `handle` IDs for each rule.
- **Why:** handles let you remove/replace one exact rule without rebuilding a whole table.
- **When:** when runtime tuning requires precise rule edits.

```bash
sudo nft -a list ruleset
```

How to read it:

- each rule line ends with `# handle 17` (example);
- that enables targeted deletion, for example: `sudo nft delete rule ip nat prerouting handle 17`.

### 4.2 `nft monitor trace`

- **What:** live packet traversal trace across hooks/chains.
- **Why:** fastest way to debug "rules exist but traffic still fails".
- **When:** any time ping/curl fails with unclear root cause.
- **Command anatomy:** `nft` (CLI) + `monitor` (event stream) + `trace` (packet-trace events only).

```bash
sudo nft monitor trace
```

Generate traffic in another terminal:

```bash
curl -sI http://127.0.0.1:8080 >/dev/null
```

If trace is silent, most often packet `nftrace` flag is not set.
For manual flow, add a temporary rule:

```bash
# enable tracing for localhost:8080 path
sudo nft insert rule ip nat output ip daddr 127.0.0.1 tcp dport 8080 meta nftrace set 1

# generate traffic
curl -sI http://127.0.0.1:8080 >/dev/null

# find handle of temporary trace rule
sudo nft -a list chain ip nat output

# remove temporary rule after test
sudo nft delete rule ip nat output handle <HANDLE>
```

Stop trace:

```bash
# in monitor terminal
Ctrl+C
```

How to interpret:

- if trace passes through `output` and `postrouting`, local DNAT path is active;
- if trace never reaches expected chain, check interface/address/port matches.

### 4.3 `tcpdump` as packet proof

- **What:** captures actual packets on an interface.
- **Why:** confirms wire-level traffic, not only logical rule matches.
- **When:** when you need hard evidence for reports or incident notes.

```bash
# sudo tcpdump -D
IF="$(ip -o route show to default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo timeout 8 tcpdump -i "$IF" -nn -w /tmp/lesson11_8080.pcap 'tcp port 8080'
```

For localhost/hairpin checks, `-i any` is usually more useful:

```bash
sudo timeout 8 tcpdump -i any -nn -w /tmp/lesson11_8080_any.pcap 'tcp port 8080'
```

### 4.4 Practical Optional path

1. Verify baseline `curl` works.
2. Start `nft monitor trace`, repeat `curl`.
3. Confirm trace uses expected hooks/chains.
4. Compare counters before/after request.
5. Capture a short `tcpdump` when deeper proof is needed.

---

## 5. Advanced Topics (Ops-Grade)

The Advanced block answers: "How do I run this safely in operations, not only in a one-time lab?"

### 5.1 Packet path map

```text
external client -> prerouting(dnat) -> forward -> postrouting(snat/masquerade) -> namespace
host localhost -> output(dnat) -> postrouting(snat hairpin) -> namespace
namespace -> postrouting(masquerade) -> WAN
```

Why this map matters: it tells you exactly which hook to inspect first for each symptom.

### 5.2 Symptom-driven troubleshooting

| Symptom | Where to inspect | Common cause | Action |
|---|---|---|---|
| `curl 127.0.0.1:8080` fails | `chain output`, `postrouting` | missing output dnat/sn​at | add output DNAT and hairpin SNAT |
| `ns -> internet` fails | `ip_forward`, `postrouting` | missing forwarding/masquerade | enable sysctl + MASQUERADE |
| rules exist but no traffic | counters/trace | wrong rule match | verify interface/address/port matches |

Fast reading logic:

- rule counter stays `0` after test traffic -> packet did not hit this rule;
- counter grows but session still fails -> inspect next stage in return path (often SNAT/route issue).

### 5.3 Persistence workflow (with rollback)

1. Create backup:

```bash
sudo cp -a /etc/nftables.conf /etc/nftables.conf.bak.$(date +%F_%H%M%S)
```

2. Validate syntax before apply (`-c` = check only):

```bash
sudo nft -c -f /etc/nftables.conf
```

3. Apply config:

```bash
sudo nft -f /etc/nftables.conf
```

4. Enable startup:

```bash
sudo systemctl enable --now nftables
```

5. Reboot-check that rules are restored.

Rollback flow:

```bash
# if rollback is needed:
# sudo cp /etc/nftables.conf.bak.YYYY-MM-DD_HHMMSS /etc/nftables.conf
# sudo nft -c -f /etc/nftables.conf
# sudo systemctl restart nftables
```

### 5.4 `iptables` vs `nft` backend

Avoid mixing unmanaged changes from both stacks in one lab path. Use one consistent control plane.

### 5.5 UFW + nft: avoiding conflicts

In this lesson, direct `nft` changes should stay limited to `table ip nat`.
If UFW is enabled on your host:

1. do not run global `flush ruleset`;
2. change only lesson-specific NAT table;
3. after lab, run `sudo ufw status verbose` and verify baseline policy is intact.

### 5.6 Advanced runbook

1. Apply lab:
`./lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh`
2. Validate connectivity and counters:
`./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh`
3. Run trace and short pcap capture.
4. Execute persistence cycle (`backup -> nft -c -> nft -f -> systemctl enable`).
5. Cleanup:
`./lessons/11-nftables-nat-dnat-persistence/scripts/cleanup-nft-netns.sh`

---

## 6. Scripts in This Lesson

Scripts in this lesson are an **automation**, not the mandatory starting point.
Recommended learning order: do the flow manually first, then compare with script automation.

### 6.1 Manual Core flow (do once without script)

```bash
# 1) netns + veth
sudo ip netns del lab11 2>/dev/null || true
sudo ip netns add lab11
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns lab11

# 2) addresses + route
sudo ip addr add 10.10.0.1/24 dev veth0
sudo ip link set veth0 up
sudo ip -n lab11 addr add 10.10.0.2/24 dev veth1
sudo ip -n lab11 link set veth1 up
sudo ip -n lab11 link set lo up
sudo ip -n lab11 route add default via 10.10.0.1

# 3) forwarding + hairpin support
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.veth0.route_localnet=1

# 3.1) FORWARD allow (required when host policy FORWARD=DROP)
IF="$(ip -o route show to default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo iptables -C FORWARD -i veth0 -o "$IF" -s 10.10.0.0/24 -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -i veth0 -o "$IF" -s 10.10.0.0/24 -j ACCEPT
sudo iptables -C FORWARD -i "$IF" -o veth0 -d 10.10.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
  sudo iptables -A FORWARD -i "$IF" -o veth0 -d 10.10.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 4) namespace service
sudo ip netns exec lab11 bash -lc 'echo nameserver 1.1.1.1 >/etc/resolv.conf'
sudo ip netns exec lab11 bash -lc 'python3 -m http.server 8080 --bind 10.10.0.2 >/tmp/lab11_http.log 2>&1 & echo $! >/tmp/lab11_http.pid'

# 5) ruleset -> apply
cat > /tmp/lesson11.nft <<EOF
table ip nat {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "$IF" tcp dport 8080 counter dnat to 10.10.0.2:8080
  }
  chain output {
    type nat hook output priority dstnat; policy accept;
    ip daddr 127.0.0.1 tcp dport 8080 counter dnat to 10.10.0.2:8080
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip daddr 10.10.0.2 tcp dport 8080 counter snat to 10.10.0.1
    ip saddr 10.10.0.0/24 oifname != "lo" counter masquerade
  }
}
EOF

sudo nft delete table ip nat 2>/dev/null || true
sudo nft -f /tmp/lesson11.nft
```

### 6.2 Scripts (automation)

Artifacts:

- `lessons/11-nftables-nat-dnat-persistence/scripts/`

```bash
chmod +x lessons/11-nftables-nat-dnat-persistence/scripts/*.sh

./lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh --help
./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh --help
./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh --trace-once
./lessons/11-nftables-nat-dnat-persistence/scripts/cleanup-nft-netns.sh --help
```

`setup-nft-netns.sh` automatically adds FORWARD allow rules for the lab subnet when needed on the current host.

---

## 7. Mini-lab (Core Path, Manual First)

If you already completed manual flow from section 6.1, run only checks:

```bash
sudo ip netns exec lab11 ping -c 1 10.10.0.1
sudo ip netns exec lab11 ping -c 1 1.1.1.1
curl -sI http://127.0.0.1:8080 | head -n 5

sudo nft list table ip nat
```

If upstream blocks outbound ICMP, validate egress via TCP instead:

```bash
sudo ip netns exec lab11 curl -sS --max-time 5 https://ifconfig.io/ip
```

If you want fully automated path instead of manual setup:

```bash
./lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh
./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh
```

Checklist:

- namespace reaches gateway;
- namespace reaches external network;
- localhost DNAT returns HTTP 200;
- nat counters increase.

---

## 8. Extended Lab (Optional + Advanced)

```bash
# Trace in one terminal
sudo nft monitor trace

# Trigger traffic in another
./lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh --trace-once

# Packet capture proof
IF="$(ip -o route show to default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
sudo timeout 12 tcpdump -i any -nn -w /tmp/lesson11_8080_any.pcap 'tcp port 8080' &
sleep 1
curl -sI http://127.0.0.1:8080 >/dev/null
HOST_EXT_IP="$(ip -4 -o addr show "$IF" | awk '{print $4}' | cut -d/ -f1 | head -1)"
curl -sI "http://$HOST_EXT_IP:8080" >/dev/null
wait

# Persistence checks
sudo nft -c -f /etc/nftables.conf
sudo systemctl enable --now nftables
```

---

## 9. Cleanup

```bash
./lessons/11-nftables-nat-dnat-persistence/scripts/cleanup-nft-netns.sh
rm -f /tmp/lesson11_8080.pcap /tmp/lesson11_8080_any.pcap
```

---

## 10. Lesson Summary

- **What I learned:** building NAT/DNAT flow with `nftables` using counters and trace.
- **What I practiced:** netns+veth topology, localhost/external DNAT, runtime and persistence checks.
- **Advanced skills:** symptom-driven debugging with `nft monitor trace` and rule counters.
- **Operational focus:** minimal blast radius (table-level changes), verify before/after, clean teardown.
- **Repo artifacts:** `lessons/11-nftables-nat-dnat-persistence/scripts/`, `lessons/11-nftables-nat-dnat-persistence/scripts/README.md`.
