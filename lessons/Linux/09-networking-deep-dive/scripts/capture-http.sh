#!/usr/bin/env bash
# Description: Timed tcpdump capture for HTTP/HTTPS into pcap.
# Usage: capture-http.sh [seconds] [output_dir]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  capture-http.sh [seconds] [output_dir]

Examples:
  ./lessons/09-networking-deep-dive/scripts/capture-http.sh
  ./lessons/09-networking-deep-dive/scripts/capture-http.sh 8
  ./lessons/09-networking-deep-dive/scripts/capture-http.sh 10 /tmp/lesson09-captures
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

dur="${1:-5}"
outdir="${2:-lessons/09-networking-deep-dive/labs/captures}"

if [[ ! "$dur" =~ ^[0-9]+$ ]]; then
  echo "ERROR: seconds must be an integer" >&2
  exit 2
fi

if ! command -v tcpdump >/dev/null 2>&1; then
  echo "ERROR: tcpdump not found (install: sudo apt-get install -y tcpdump)" >&2
  exit 1
fi

iface="$(ip -4 route get 1.1.1.1 | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
if [[ -z "${iface:-}" ]]; then
  echo "ERROR: could not detect default network interface" >&2
  exit 1
fi

mkdir -p "$outdir"
file="${outdir}/http_$(date +%Y%m%d_%H%M%S).pcap"

echo "Capturing ${dur}s on ${iface} -> ${file} (tcp port 80 or 443)"
sudo timeout -- "$dur" tcpdump -i "$iface" -nn -s 0 -U -w "$file" 'tcp port 80 or tcp port 443'

echo "Saved: $file"
