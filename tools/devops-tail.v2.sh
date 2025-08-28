#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
usage(){ echo "Usage: $0 <unit> [-s 'since'] [-n lines] [-f] [-p PRIORITY]"; }
since="10 min ago"; lines=50; follow=0; prio=""; unit=""
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
if [[ $# -gt 0 && "${1:-}" != -* ]]; then
unit="$1"
shift
fi
if [[ $# -gt 0 ]]; then
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
shift $((OPTIND-1)) || true
fi
[[ -n "$unit" ]] || { usage; exit 1; }
[[ "$lines" =~ ^[0-9]+$ ]] && (( lines>=1 )) || { echo "Invalid -n LINES: $lines" >&2; exit 1; }
echo "== systemctl status $unit =="
systemctl status "$unit" --no-pager | sed -n '1,12p' || true
args=(-u "$unit" --since "$since" -n "$lines" --no-pager)
[[ -n "$prio" ]] && args+=(-p "$prio")
(( follow )) && args+=(-f)
printf '== journalctl %s ==\n' "$(printf '%s ' "${args[@]}")"
journalctl "${args[@]}"
