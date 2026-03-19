# Network Check Scripts (Lesson 03)

This folder contains two helper scripts for networking diagnostics.

## Files

- `core-check.sh`  
  Minimal troubleshooting flow:
  - `ip -br addr`
  - `ip route`
  - `ping` to `1.1.1.1`
  - `ping` to `google.com`
  - `traceroute` to `1.1.1.1`
  - DNS check via `dig +short` (or `nslookup` fallback)

- `deep-check.sh`  
  Optional + advanced diagnostics:
  - `resolvectl status`
  - `curl -I`
  - `wget --spider`
  - `dig` record queries / resolver comparison / `+trace`
  - `mtr` snapshot
  - optional `--hosts-test` (temporary `/etc/hosts` edit)

## Requirements

Required for most checks:

- `ip` (iproute2)
- `ping` (iputils-ping)
- `traceroute`
- one of: `dig` (`dnsutils`) or `nslookup`

Used by deep checks:

- `resolvectl` (systemd-resolved environments)
- `curl`
- `wget`
- `mtr`

Optional:

- `sudo` (required for `--hosts-test`)

## Usage

From repo root:

```bash
lessons/03-networking-foundations/scripts/core-check.sh /tmp/net-lab
```

```bash
lessons/03-networking-foundations/scripts/deep-check.sh /tmp/net-lab
lessons/03-networking-foundations/scripts/deep-check.sh --hosts-test /tmp/net-lab
```

Help:

```bash
lessons/03-networking-foundations/scripts/core-check.sh -h
lessons/03-networking-foundations/scripts/core-check.sh --help
lessons/03-networking-foundations/scripts/deep-check.sh -h
lessons/03-networking-foundations/scripts/deep-check.sh --help
```

## Output

Each run creates a timestamped run log directory:

- `core-check_YYYYmmdd_HHMMSS/`
- `deep-check_YYYYmmdd_HHMMSS/`

Common output artifacts:

- `ip_addr.txt`
- `ip_route.txt`
- `dns_lookup.txt` (core)
- `dns_status.txt` (deep)
- `mtr_1_1_1_1.txt` (deep, if `mtr` exists)

Each command also writes:

- `<command_name>.out`
- `<command_name>.err`

## Exit Codes

- `0` - completed without command failures
- `1` - one or more commands failed
- `2` - arguments failures

Skipped checks (missing tools) are reported but do not always fail the run.

## Safety Notes

- `deep-check.sh --hosts-test` modifies `/etc/hosts` and then removes the test record.
- Use `--hosts-test` only when you understand the local DNS override behavior.
