# NAT/DNAT Netns Scripts (Lesson 10)

This folder contains helper scripts for lesson 10 (`netns`, NAT, DNAT, cleanup).

## Files

- `setup-netns-nat.sh`
  - create namespace lab, enable routing, apply NAT + DNAT, start HTTP server in namespace
- `check-netns-nat.sh`
  - validate connectivity and show useful iptables counters
- `cleanup-netns-nat.sh`
  - remove rules, namespace/veth, and restore sysctl values from state file

## Requirements

- `bash`
- `sudo`
- `ip` (iproute2), `iptables`, `sysctl`, `curl`, `python3`
- optional: `tcpdump`, `ufw` for extended checks

## Usage

From repo root:

```bash
chmod +x lessons/10-networking-nat-dnat-netns-ufw/scripts/*.sh

lessons/10-networking-nat-dnat-netns-ufw/scripts/setup-netns-nat.sh
lessons/10-networking-nat-dnat-netns-ufw/scripts/check-netns-nat.sh
lessons/10-networking-nat-dnat-netns-ufw/scripts/cleanup-netns-nat.sh
```

## Safety Notes

- Scripts modify host networking and firewall rules via `sudo`.
- Run only on lab hosts where temporary routing/NAT changes are acceptable.
- On remote servers, always preserve SSH access before touching UFW defaults.
