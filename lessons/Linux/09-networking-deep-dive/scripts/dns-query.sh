#!/usr/bin/env bash
# Description: Query common DNS record types with dig.
# Usage: dns-query.sh <domain> [@server]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  dns-query.sh <domain> [@server]

Examples:
  ./lessons/09-networking-deep-dive/scripts/dns-query.sh google.com
  ./lessons/09-networking-deep-dive/scripts/dns-query.sh google.com @1.1.1.1
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

domain="${1:-}"
server="${2:-}"

if [[ -z "$domain" ]]; then
  echo "ERROR: <domain> is required" >&2
  usage
  exit 2
fi

if ! command -v dig >/dev/null 2>&1; then
  echo "ERROR: dig not found (install: sudo apt-get install -y dnsutils)" >&2
  exit 1
fi

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
