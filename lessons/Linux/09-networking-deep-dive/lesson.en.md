# lesson_09

# Networking Deep Dive: `iproute2`, `ss`, `dig`, `tcpdump`, `ufw`, `netns`

**Date:** 2025-09-15  
**Topic:** Deep networking diagnostics: sockets, DNS, packet capture, baseline firewall policy, and isolated networks with namespaces.  
**Daily goal:** Troubleshoot by chain `interface -> route -> socket -> dns -> packet -> policy` and reproduce findings safely in a lab.
**Bridge:** [08-11 Networking + Text Bridge](../00-foundations-bridge/08-11-networking-text-bridge.md) for deep explanations and troubleshooting across lessons 8-11.
**Legacy:** original old notes remain in `lessons/09-networking-deep-dive/lesson_09(legacy).md`.

---

## 1. Core Concepts

### 1.1 Troubleshooting chain: from symptom to cause

Practical triage order:

1. Is interface/address/route correct (`ip`)?
2. Is anything listening (`ss`)?
3. Does name resolution work (`dig`/`resolvectl`)?
4. What packets actually flow (`tcpdump`)?
5. Is policy blocking traffic (`ufw`)?

This order avoids random command hopping.

### 1.2 Why `iproute2` is foundational

`iproute2` (`ip`, `ss`) replaced legacy tools (`ifconfig`, `netstat`):

- consistent output model;
- better filters;
- better fit for modern Linux systems.

### 1.3 Sockets vs ports

- port: numeric endpoint (for example `:22`);
- socket: protocol + local/remote address + local/remote port;
- a process may listen correctly, while DNS/route/firewall is the real issue.

### 1.4 DNS is part of the service path

When "service is down", root cause is often before HTTP itself:

- wrong DNS answer;
- wrong resolver;
- UDP/TCP 53 path issue;
- stale cache.

### 1.5 Why `tcpdump` matters

`tcpdump` is for cases where app logs are insufficient:

- did SYN leave the host;
- did DNS query leave and response return;
- is there retransmission/timeout behavior.

Capture must stay short and filtered.

### 1.6 Firewall safety principle

`ufw` is useful but dangerous if applied blindly:

- define rules first,
- enable policy second,
- verify critical access immediately.

On remote servers without out-of-band access, apply firewall changes very carefully.

### 1.7 Why `netns` in this lesson

`ip netns` gives safe networking sandboxes:

- isolated interfaces and routes;
- repeatable two-host topology without VMs;
- fast setup and teardown.

---

## 2. Command Priority (What to Learn First)

### Core (must know now)

- `ip -br a`
- `ip r`
- `ss -tulpn`
- `ss -tan state established`
- `dig +short A/AAAA <domain>`
- `resolvectl status`
- `tcpdump -i <if> -w <file.pcap> 'filter'`
- `ufw status verbose`

### Optional (after core)

- `ss` filters `( sport = :N or dport = :N )`
- `curl -w` timing metrics
- `dig +noall +answer`
- `dig +trace`
- `tcpdump -r <file.pcap>`

### Advanced (operations-grade)

- safe UFW baseline + immediate validation after apply
- `ip netns` + `veth` for reproducible network lab testing
- script-first wrappers for recurring diagnostics

---

## 3. Core Commands: What / Why / When

### `ip -br a`

- **What:** compact interface/address overview.
- **Why:** validate host L3 state at a glance.
- **When:** first command in almost any network triage.

```bash
ip -br a
```

### `ip r`

- **What:** route table.
- **Why:** confirm default route and subnet paths.
- **When:** when destination IP is unreachable.

```bash
ip r
```

### `ss -tulpn`

- **What:** listening TCP/UDP sockets with process info.
- **Why:** verify if expected service really listens.
- **When:** after interface/route checks.

```bash
sudo ss -tulpn | head -n 30
```

### `ss -tan state established`

- **What:** active TCP sessions.
- **Why:** inspect real peer connections.
- **When:** "who talks to whom" investigations.

```bash
sudo ss -tan state established | head -n 30
```

### `dig +short A/AAAA <domain>`

- **What:** quick DNS result by record type.
- **Why:** validate resolution fast with low noise.
- **When:** host reachable by IP but not by name.

```bash
dig +short A google.com
dig +short AAAA google.com
```

### `resolvectl status`

- **What:** active resolvers/search domains (systemd-resolved).
- **Why:** confirm which resolver path your host uses.
- **When:** unstable or unexpected DNS behavior.

```bash
resolvectl status | sed -n '1,120p'
```

### `tcpdump` capture to file

- **What:** write packet stream to pcap.
- **Why:** capture objective network evidence for offline analysis.
- **When:** app logs do not explain connectivity behavior.

```bash
IF="$(ip -o route show to default | awk '{print $5; exit}')"
sudo timeout 8 tcpdump -i "$IF" -nn -s 0 -w /tmp/lesson09_https.pcap 'tcp port 443'
tcpdump -nn -r /tmp/lesson09_https.pcap | head -n 20
```

### `ufw status verbose`

- **What:** current firewall policy and status.
- **Why:** verify effective policy before/after rule changes.
- **When:** always around firewall operations.

```bash
sudo ufw status verbose
```

---

## 4. Optional Commands (After Core)

### `ss` by port/process

- **What:** targeted filter by port/process.
- **Why:** reduce noise in large socket output.
- **When:** focused service-specific triage.

```bash
sudo ss -tulpn '( sport = :22 or sport = :80 )'
sudo ss -tulpn | grep -Ei 'nginx|ssh|docker' || true
```

### `curl -w` timing

- **What:** DNS/connect/TLS/TTFB timing breakdown.
- **Why:** identify where HTTP latency is introduced.
- **When:** "site is slow" or intermittent response reports.

```bash
curl -sS -o /dev/null -L \
  -w '{"code":%{http_code},"dns":%{time_namelookup},"connect":%{time_connect},"tls":%{time_appconnect},"ttfb":%{time_starttransfer},"total":%{time_total}}\n' \
  https://google.com
```

### `dig +noall +answer` and `dig +trace`

- **What:** compact answer view + delegation trace.
- **Why:** isolate where DNS path breaks.
- **When:** resolver disagreement, split-horizon, partial failures.

```bash
dig +noall +answer A google.com
dig +trace google.com | sed -n '1,60p'
```

### DNS-only `tcpdump`

- **What:** capture only DNS packets.
- **Why:** verify query/response path existence.
- **When:** DNS appears configured but fails in practice.

```bash
IF="$(ip -o route show to default | awk '{print $5; exit}')"
sudo timeout 10 tcpdump -i "$IF" -vv -n 'udp port 53 or tcp port 53'
```

---

## 5. Advanced Topics (Ops-Grade)

### 5.1 Safe UFW baseline

Apply sequence:

1. inspect current state;
2. set default policy;
3. allow critical traffic explicitly;
4. enable firewall;
5. validate immediately.

```bash
sudo ufw status verbose || true
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in on lo
sudo ufw allow out on lo
sudo ufw allow 22/tcp
sudo ufw enable
sudo ufw status numbered
```

Constraint:

- on remote hosts, apply only with a rollback plan.

### 5.2 Namespace lab as reproducible environment

With `ip netns` + `veth`, you can quickly create a "two host" topology:

- verify cross-namespace ping;
- run service in one namespace;
- access it from another namespace;
- remove all artifacts cleanly.

### 5.3 Script-first diagnostics

Recurring tasks are wrapped in scripts in this lesson:

- socket filtering;
- DNS quick queries;
- short packet capture;
- namespace mini-lab.

This reduces manual mistakes and increases repeatability.

---

## 6. Scripts in This Lesson

Artifacts are located in:

- `lessons/09-networking-deep-dive/scripts/`

Set execution bit once:

```bash
chmod +x lessons/09-networking-deep-dive/scripts/*.sh
```

Help checks:

```bash
./lessons/09-networking-deep-dive/scripts/net-ports.sh --help
./lessons/09-networking-deep-dive/scripts/dns-query.sh --help
./lessons/09-networking-deep-dive/scripts/capture-http.sh --help
./lessons/09-networking-deep-dive/scripts/netns-mini-lab.sh --help
```

Short run examples:

```bash
./lessons/09-networking-deep-dive/scripts/net-ports.sh --listen --process ssh
./lessons/09-networking-deep-dive/scripts/dns-query.sh google.com @1.1.1.1
./lessons/09-networking-deep-dive/scripts/capture-http.sh 6
./lessons/09-networking-deep-dive/scripts/netns-mini-lab.sh
```

---

## 7. Mini-lab (Core Path)

```bash
mkdir -p lessons/09-networking-deep-dive/labs/captures

ip -br a
ip r

sudo ss -tulpn | head -n 20
sudo ss -tan state established | head -n 20

dig +short A google.com
resolvectl status | sed -n '1,60p'

IF="$(ip -o route show to default | awk '{print $5; exit}')"
sudo timeout 5 tcpdump -i "$IF" -nn -s 0 -w /tmp/lesson09_core.pcap 'tcp port 443'
tcpdump -nn -r /tmp/lesson09_core.pcap | head -n 20
```

Checklist:

- you can identify default route and active interface;
- you can verify which process listens on target ports;
- you can confirm expected DNS resolution;
- you can capture and read a short pcap offline.

---

## 8. Extended Lab (Optional + Advanced)

```bash
# 1) HTTP timing
curl -sS -o /dev/null -L \
  -w '{"code":%{http_code},"dns":%{time_namelookup},"connect":%{time_connect},"tls":%{time_appconnect},"ttfb":%{time_starttransfer},"total":%{time_total}}\n' \
  https://google.com

# 2) DNS deep checks
./lessons/09-networking-deep-dive/scripts/dns-query.sh google.com
./lessons/09-networking-deep-dive/scripts/dns-query.sh google.com @8.8.8.8

# 3) UFW baseline (only if you understand rollback risk)
sudo ufw status verbose || true
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw enable
sudo ufw status numbered

# 4) namespace mini-lab
./lessons/09-networking-deep-dive/scripts/netns-mini-lab.sh
```

---

## 9. Cleanup

```bash
sudo ufw disable || true
sudo ip netns del blue 2>/dev/null || true
sudo ip netns del red 2>/dev/null || true
rm -f /tmp/lesson09_core.pcap
```

---

## 10. Lesson Summary

- **What I learned:** a practical deep-dive workflow with `ip`, `ss`, `dig`, `tcpdump`, `ufw`, and `netns`.
- **What I practiced:** route/socket triage, DNS checks, short packet captures, baseline firewall policy, and isolated network lab execution.
- **Advanced skills:** moving from ad-hoc commands to repeatable script-based diagnostics.
- **Operational focus:** collect facts first, change policy second; apply firewall changes with rollback plan; keep captures short and filtered.
- **Repo artifacts:** `lessons/09-networking-deep-dive/scripts/`, `lessons/09-networking-deep-dive/scripts/README.md`.
