#!/usr/bin/env bash
# Description: List sockets via ss with optional state/port/process filters.
# Usage: net-ports.sh [--listen|--established] [--port N] [--process NAME]
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  net-ports.sh [--listen|--established] [--port N] [--process NAME]

Examples:
  ./lessons/09-networking-deep-dive/scripts/net-ports.sh --listen
  ./lessons/09-networking-deep-dive/scripts/net-ports.sh --established --port 443
  ./lessons/09-networking-deep-dive/scripts/net-ports.sh --listen --process ssh
USAGE
}

listen=0
established=0
port=""
proc=""

for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    usage
    exit 0
  fi
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --listen)      listen=1; shift ;;
    --established) established=1; shift ;;
    --port)
      [[ $# -ge 2 ]] || { echo "ERROR: --port requires value" >&2; usage; exit 2; }
      port="$2"; shift 2 ;;
    --process)
      [[ $# -ge 2 ]] || { echo "ERROR: --process requires value" >&2; usage; exit 2; }
      proc="$2"; shift 2 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if (( listen && established )); then
  echo "ERROR: choose either --listen or --established" >&2
  exit 2
fi

if [[ -n "$port" && ! "$port" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --port must be an integer" >&2
  exit 2
fi

cmd=(sudo ss -tulpn)
args=(-H)

if (( listen )); then
  args+=(state listening)
elif (( established )); then
  args+=(state established)
fi

if [[ -n "$port" ]]; then
  args+=("( sport = :$port or dport = :$port )")
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
