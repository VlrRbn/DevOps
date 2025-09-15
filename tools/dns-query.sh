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
