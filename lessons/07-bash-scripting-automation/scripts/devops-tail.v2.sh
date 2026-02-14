#!/usr/bin/env bash
# Description: Flexible journal viewer for a systemd unit with since/lines/follow/priority.
# Usage: devops-tail.v2.sh <unit> [-s 'since'] [-n lines] [-f] [-p PRIORITY]
# Notes: Prints status summary then journalctl output.
set -Eeuo pipefail
IFS=$'\n\t'

usage() {
  cat <<'USAGE'
Usage:
  devops-tail.v2.sh <unit> [-s 'since'] [-n lines] [-f] [-p PRIORITY]

Examples:
  ./lessons/07-bash-scripting-automation/scripts/devops-tail.v2.sh cron
  ./lessons/07-bash-scripting-automation/scripts/devops-tail.v2.sh ssh -s "1 hour ago" -n 100
  ./lessons/07-bash-scripting-automation/scripts/devops-tail.v2.sh ssh -p warning -f
USAGE
}

since="10 min ago"
lines=50
follow=0
prio=""
unit=""

for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    usage
    exit 0
  fi
done

if [[ $# -gt 0 && "${1:0:1}" != "-" ]]; then
  unit="$1"
  shift
fi

OPTIND=1
while getopts ":s:n:fp:h" opt; do
  case "$opt" in
    s) since="$OPTARG" ;;
    n) lines="$OPTARG" ;;
    f) follow=1 ;;
    p) prio="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) usage; exit 1 ;;
  esac
done
shift $((OPTIND-1))

if [[ -z "$unit" && $# -gt 0 && "${1:0:1}" != "-" ]]; then
  unit="$1"
  shift
fi

[[ -n "$unit" ]] || { usage; exit 1; }
[[ $# -eq 0 ]] || { usage; exit 1; }
[[ "$lines" =~ ^[0-9]+$ ]] && (( lines>=1 )) || { echo "Invalid -n LINES: $lines" >&2; exit 1; }

echo "== systemctl status $unit =="
systemctl status "$unit" --no-pager | sed -n '1,12p' || true

args=(-u "$unit" --since "$since" -n "$lines" --no-pager)
[[ -n "$prio" ]] && args+=(-p "$prio")
(( follow )) && args+=(-f)

printf '== journalctl %s ==\n' "$(printf '%s ' "${args[@]}")"
journalctl "${args[@]}"
