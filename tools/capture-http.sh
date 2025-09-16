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
