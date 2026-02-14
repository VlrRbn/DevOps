# Networking Deep Dive Scripts (Lesson 09)

This folder contains helper scripts for lesson 09 networking diagnostics and lab automation.

## Files

- `net-ports.sh`
  - socket/port triage via `ss` with optional filters
- `dns-query.sh`
  - query common DNS record types (`A/AAAA/CNAME/NS/TXT`)
- `capture-http.sh`
  - timed `tcpdump` capture to a pcap file
- `netns-mini-lab.sh`
  - create two namespaces, run ping + HTTP check, cleanup

## Requirements

- `bash`
- `sudo`
- networking tools: `ip`, `ss`, `dig`, `tcpdump`, `curl`
- `python3` (for namespace HTTP test)

## Usage

From repo root:

```bash
chmod +x lessons/09-networking-deep-dive/scripts/*.sh

lessons/09-networking-deep-dive/scripts/net-ports.sh --listen
lessons/09-networking-deep-dive/scripts/dns-query.sh google.com @1.1.1.1
lessons/09-networking-deep-dive/scripts/capture-http.sh 8
lessons/09-networking-deep-dive/scripts/netns-mini-lab.sh
```

## Safety Notes

- `capture-http.sh` and `netns-mini-lab.sh` use `sudo` and make temporary network-level changes.
- Do not run capture scripts on hosts where packet capture is not allowed by policy.
- Namespace script cleans up namespaces at the end, but rerun safely if interrupted.
