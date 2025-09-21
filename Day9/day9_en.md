# day9_en

# Networking Deep Dive

---

**Date:** **2025-09-15**

**Topic:** iproute2, ss, tcpdump, DNS, firewall

---

## Goals

- Inspect interfaces, routes, and rules with **iproute2** (`ip a|l|r`, brief views).
- Triage open **ports/sockets** with **ss**; find who listens, who talks, and on which IPs.
- Query and troubleshoot **DNS** with `dig`/`resolvectl`.
- Capture/inspect packets with **tcpdump** (safe filters, write/read pcap).
- Apply a **local firewall** policy (UFW) **safely**, test connectivity.

---

## Environment prep

```bash
mkdir -p labs/day9/captures labs/day9/netns tools
ip -br a
ip r
```

### 1) Sockets & ports triage (ss)

Find listeners and top talkers.

```bash
# who is listening (TCP/UDP), with PIDs
sudo ss -tulpn | head -20

# established TCP with peer addresses
sudo ss -tan state established | head -20

# filter by port/process
sudo ss -tulpn '( sport = :22 or sport = :80 )'
sudo ss -tulpn | grep -i 'nginx\|ssh\|docker' || true
```

**Notes:** prefer `ss` over deprecated `netstat`; use `state listening|established|time-wait` filters; `-p` needs sudo to show PIDs.

### 2) Quick TCP/HTTP check (ncat + curl)

Create a tiny TCP server/client and check HTTP timings.

```bash
# (sudo apt-get install -y ncat)
# 2.1 TCP echo (server) — run in one terminal
ncat -v -lk 9000 --exec /bin/cat

# 2.2 Client (other terminal): type hello and see echo
ncat -v 127.0.0.1 9000

# 2.3 HTTP timing with curl (multiline)
curl -sS -o /dev/null \
  -w 'http_code:%{http_code}\nnamelookup:%{time_namelookup}\nconnect:%{time_connect}\nappconnect:%{time_appconnect}\nstarttransfer:%{time_starttransfer}\nredirect:%{time_redirect}\ntotal:%{time_total}\n' \
  https://google.com
  
# 2.4 HTTP timing with curl (JSON for scripts)
curl -sS -o /dev/null -L \
  -w '{"code":%{http_code},"dns":%{time_namelookup},"connect":%{time_connect},"tls":%{time_appconnect},"ttfb":%{time_starttransfer},"redir":%{time_redirect},"total":%{time_total}}\n' \
  https://google.com
  
# 2.5 HTTP timing with curl (HTTP without TLS)
curl -sS -o /dev/null \
  -w 'code:%{http_code} ttfb:%{time_starttransfer} total:%{time_total}\n' \
  https://google.com
```

**Notes:**  localhost may resolve to IPv6 (`::1`). Force IPv4 with `-4` to `curl`/`ncat` if needed.

### 3) DNS triage (dig / resolvectl)

```bash
# A/AAAA records
dig +short A google.com
dig +short AAAA google.com

# Which resolvers & search domains are active (systemd-resolved)
resolvectl status | sed -n '1,80p'

# Query against a specific DNS server
dig @1.1.1.1 +short A google.com

# Who responded and what exactly
dig +noall +answer A google.com

# Trace delegation (root->…); add +tcp if UDP/53 is cut somewhere
dig +trace google.com | sed -n '1,40p'
```

**Notes:** `dig +short` is great for quick checks; `resolvectl` shows current resolver stack (systemd-resolved environments).

### 4) tcpdump basics (capture safely)

Capture what need; write pcap for offline view.

```bash
# detect default interface (rough)
ip route get 1.1.1.1 | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'

# more reliable: 
IF="$(ip -o route show to default | awk '{print $5; exit}')"
echo "Using IF=$IF"

# 4.1 capture HTTPS to file (5s)
sudo timeout 5 tcpdump -i "$IF" -s 0 -nn -w "labs/day9/captures/https_$(date +%H%M%S).pcap" 'tcp port 443'

# 4.2 read back (no root needed)
tcpdump -nn -r labs/day9/captures/*.pcap | head -20
tcpdump -nn -r "$(ls -t labs/day9/captures/*.pcap | head -1)" | head -40     # if there are several files, read the latest one

# 4.3 capture only DNS
sudo timeout 15 tcpdump -i "$IF" -vv -n 'udp port 53 or tcp port 53'     # 127.0.0.53 (lo) or any
```

**Notes:** use `timeout` to avoid long captures; filters like `'host 1.2.3.4'`, `'tcp port 443'`, `'udp'` reduce noise.

### 5) UFW firewall — local policy (safe)

```bash
sudo ufw status verbose || true
sudo ufw app list || true

sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow in  on lo
sudo ufw allow out on lo

sudo ufw allow in on lo to any port 22 proto tcp
sudo ufw allow in on lo to any port 80  proto tcp
sudo ufw allow in on lo to any port 9000 proto tcp

# allow SSH (loopback/local dev)
sudo ufw enable
sudo ufw status numbered
sudo ufw show added
```

**UFW Security: Do not enable UFW on a remote server via SSH unless there is out-of-band access.**

**Test connectivity**

```bash
# should still work
curl -sI https://www.google.com

# local nginx
curl -sI http://127.0.0.1/

# test local port 9000 if server is running
nc -z -w1 127.0.0.1 9000 || true
```

To later disable: `sudo ufw disable`.

### 6) Network namespaces mini-lab

create `run.sh` — build two isolated hosts connected via a veth pair.

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# 6.0 clean start (silent if not)
for ns in blue red; do sudo ip netns del "$ns" 2>/dev/null || true; done

# 6.1 create namespaces
sudo ip netns add blue
sudo ip netns add red

# 6.2 create veth and attach ends
sudo ip link add veth-blue type veth peer name veth-red
sudo ip link set veth-blue netns blue
sudo ip link set veth-red  netns red

# 6.3 address and up
sudo ip -n blue addr add 10.10.10.1/24 dev veth-blue
sudo ip -n red  addr add 10.10.10.2/24 dev veth-red
sudo ip -n blue link set lo up
sudo ip -n red  link set lo up
sudo ip -n blue link set veth-blue up
sudo ip -n red  link set veth-red  up

# 6.4 ping across
sudo ip netns exec blue ping -c 2 10.10.10.2

# 6.5 tiny HTTP server in red, curl from blue
sudo ip netns exec red bash -lc 'python3 -m http.server 8080 --bind 10.10.10.2 >/dev/null 2>&1 & echo $! >/tmp/http.pid'
sudo ip netns exec blue curl -sI http://10.10.10.2:8080 | head -5

# 6.6 cleanup
sudo ip netns exec red bash -lc 'kill "$(cat /tmp/http.pid 2>/dev/null)" 2>/dev/null || true'
sudo ip netns del blue
sudo ip netns del red

# 6.7 cleanup
chmod +x labs/day9/netns/run.sh

# 6.8 start with log
./run.sh | tee "logs/run_$(date +%Y%m%d_%H%M%S).log"
```

---

## Tools

### net-ports.sh — quick socket filter

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

usage(){ echo "Usage: $0 [--listen] [--established] [--port N] [--process NAME]"; }

listen=0; estab=0; port=""; proc=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --listen)      listen=1; shift;;
    --established) estab=1;  shift;;
    --port)        port="${2:?port number required}"; shift 2;;
    --process)     proc="${2:?process name required}"; shift 2;;
    *) usage; exit 1;;
  esac
done

cmd=(sudo ss -tulpn)
args=(-H)

if (( listen && ! estab )); then
  args+=('state' 'listening')
elif (( estab && ! listen )); then
  args+=('state' 'established')
fi

if [[ -n "$port" ]]; then
  args+=('( sport = :'"$port"' or dport = :'"$port"' )')
fi

if [[ ${#args[@]} -eq 1 ]]; then
  args=()
fi

"${cmd[@]}" "${args[@]}" | {
  if [[ -n "$proc" ]]; then
    grep -i -- "$proc" || true
  else
    cat
  fi
}
```

### dns-query.sh — handy dig wrapper

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 domain [@server]"
  exit 1
fi

domain="$1"
server="${2:-}"
server_arg=()

if [[ -n "$server" ]]; then
  if [[ "$server" == @* ]]; then
    server_arg=("$server")
  else
    server_arg=("@$server")
  fi
fi

types=(A AAAA CNAME NS TXT)

for t in "${types[@]}"; do
  printf "%s:\n" "$t"
  if out="$(dig +short "$t" "$domain" "${server_arg[@]}" 2>/dev/null)"; then
    if [[ -n "$out" ]]; then
      printf "%s\n" "$out"
    else
      echo "-"
    fi
  else
    echo "error: dig failed"
  fi
  echo
done
```

### capture-http.sh — timed tcpdump to pcap

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

dur="${1:-5}"

iface="$(ip -4 route get 1.1.1.1 | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
if [[ -z "${iface:-}" ]]; then
  echo "ERROR: не удалось определить сетевой интерфейс." >&2
  exit 1
fi

outdir="labs/day9/captures"
mkdir -p "$outdir"
file="${outdir}/http_$(date +%Y%m%d_%H%M%S).pcap"

echo "Capturing ${dur}s on ${iface} -> ${file} (tcp port 80)"

if ! command -v tcpdump >/dev/null 2>&1; then
  echo "ERROR: tcpdump не установлен." >&2
  exit 1
fi

sudo timeout -- "${dur}" \
  tcpdump -i "$iface" -nn -s 0 -U -w "$file" 'tcp port 80'

echo "Saved: $file"
```

---

## Notes

- Prefer **iproute2** tools (`ip`, `ss`) over legacy ones (`ifconfig`, `netstat`).
- Use **filters** and **timeouts** in tcpdump; capture to files, inspect offline.
- On laptops, **UFW** with `deny incoming` / `allow outgoing` is a sensible default.
- Namespaces are perfect for safe experiments; always **cleanup**.

## Summary

- Performed socket triage with `ss`, verified listeners/clients.
- Practiced DNS diagnostics (`dig +short`, `resolvectl status`).
- Captured minimal, focused pcaps with `tcpdump` and validated with offline read.
- Applied a baseline UFW policy and verified connectivity.
- Built and tested an isolated two-host lab via `ip netns` + veth.

**Key takeaways:** modern Linux networking tools, disciplined filtering, and safe lab patterns (namespaces).

**Next steps:** mtr/traceroute deep dive; iptables/nftables basics; NAT & port-forwarding in namespaces; service hardening on network level.

## Artifacts

- `labs/day9/captures/*.pcap`
- `labs/day9/netns/run.sh`
- `tools/net-ports.sh`, `tools/dns-query.sh`, `tools/capture-http.sh`

## To repeat

- `sudo ss -tulpn` / `sudo ss -tan state established`
- `dig +short A/AAAA domain` · `resolvectl status`
- `tcpdump -i $IF -w file.pcap 'filter'` · `tcpdump -nn -r file.pcap | head`
- `sudo ufw default deny incoming; sudo ufw allow 22/tcp; sudo ufw enable`
- `ip netns add NAME; ip link add vethA type veth peer name vethB; …`