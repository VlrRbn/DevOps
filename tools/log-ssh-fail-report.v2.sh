#!/usr/bin/env bash
set -Eeuo pipefail
src="journal"
since="today"
top=10
all=0
usage(){ echo "Usage: $0 [--source journal|auth] [--since STR] [--top N] [--all]"; }
while [[ $# -gt 0 ]]; do
case "$1" in
--source) src="${2:-journal}"; shift 2;;
--since)  since="${2:-today}"; shift 2;;
--top)    top="${2:-10}"; shift 2;;
--all)    all=1; shift;;
-h|--help) usage; exit 0;;
*) usage; exit 1;;
esac
done
if [[ "$src" == "auth" ]]; then
pat='Failed password'
if (( all )); then
sudo zgrep -hE "$pat" /var/log/auth.log* 2>/dev/null || true
else
sudo grep -hE "$pat" /var/log/auth.log 2>/dev/null || true
fi
else
journalctl -u ssh --since "$since" -o cat | grep -E 'Failed password' || true
fi | awk '{
if (match($0, /([0-9]{1,3}\.){3}[0-9]{1,3}/, m)) { print m[0]; next }
if (match($0, /\b([0-9a-fA-F]{1,4}:){2,}[0-9a-fA-F]{1,4}\b/, m)) { print m[0]; next }
}' | sort | uniq -c | sort -nr | head -n "$top"
