#!/usr/bin/env bash
set -Eeuo pipefail
file="${1:-labs/day8/logs/sample/nginx_access.log}"
[[ -r "$file" ]] || { echo "No such log: $file" >&2; exit 1; }
awk '{if (match($0, /"([A-Z]+) ([^"]+) HTTP\/[0-9.]+"/, m)) {
method=m[1]; path=m[2];
} else next;
status=$9; ip=$1; total++; codes[status]++; hits[path]++; ips[ip]++;
if (status ~ /^[45]/) errs++;
} END {
printf "Total: %d\n", total;
printf "Error rate (4xx+5xx): %.2f%%\n", (total?100*errs/total:0);
printf "Status codes: \n"; for (c in codes) printf "  %s: %d\n", c, codes[c];
printf "Top paths: \n"; for (p in hits) printf "  %s: %d\n", p, hits[p];
printf "Unique IPs: %d\n", length(ips)+0;
}' "$file"
