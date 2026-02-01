#!/usr/bin/env bash
# Description: List TCP ports using ss with optional filters.
# Usage: net-ports.sh [--listen] [--established] [--port N] [--process NAME]
# Notes: Uses sudo ss -tulpn and optional grep by process name.
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
