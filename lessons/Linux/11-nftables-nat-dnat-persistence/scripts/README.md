# NFTables NAT/DNAT Scripts (Lesson 11)

This folder contains helper scripts for lesson 11 (`nftables`, `netns`, NAT/DNAT, cleanup).

## Files

- `setup-nft-netns.sh`
  - create netns lab, apply nft NAT/DNAT table, add FORWARD allow rules for lab subnet, start namespace HTTP service
- `check-nft-netns.sh`
  - validate connectivity and print nft nat table with counters
  - optional `--trace-once`: temporarily inject `nftrace` rule for localhost:PORT check and auto-clean it
- `cleanup-nft-netns.sh`
  - remove lab nat table, remove setup-added FORWARD rules, remove network artifacts, restore sysctl values

## Requirements

- `bash`
- `sudo`
- `ip` (iproute2), `nft`, `iptables`, `sysctl`, `curl`, `python3`
- optional: `tcpdump` for packet captures

## Usage

From repo root:

```bash
chmod +x lessons/11-nftables-nat-dnat-persistence/scripts/*.sh

lessons/11-nftables-nat-dnat-persistence/scripts/setup-nft-netns.sh
lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh
lessons/11-nftables-nat-dnat-persistence/scripts/cleanup-nft-netns.sh
```

State file used between scripts:

- `/tmp/lesson11_nft_state.env`

Trace helper mode:

```bash
# terminal A (before running check):
sudo nft monitor trace

# terminal B:
lessons/11-nftables-nat-dnat-persistence/scripts/check-nft-netns.sh --trace-once
```

## Troubleshooting

- If `check-nft-netns.sh` fails on `namespace -> internet` ping:
  - host NAT may still be fine; some networks block outbound ICMP.
  - verify TCP egress from namespace:

```bash
sudo ip netns exec lab11 curl -sS --max-time 5 https://ifconfig.io/ip
```

- If DNS resolution times out from namespace:
  - verify `FORWARD` policy/rules (`FORWARD=DROP` requires allow rules).
  - setup script adds these FORWARD allow rules automatically for the lesson subnet.

## Safety Notes

- Scripts change host networking and nft rules via `sudo`.
- Setup may add two `iptables` FORWARD allow rules for the lab subnet (to work when host FORWARD policy is DROP).
- Intended for lab hosts; do not run blindly on production servers.
- Cleanup script removes lesson NAT table and setup-added FORWARD allow rules.
