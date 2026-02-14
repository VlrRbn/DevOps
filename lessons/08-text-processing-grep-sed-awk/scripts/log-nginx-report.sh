#!/usr/bin/env bash
# Summarize nginx access log: totals, error rate, status codes, top paths, unique IPs.
# Usage: log-nginx-report.sh [logfile]
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  log-nginx-report.sh [logfile]

Examples:
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-nginx-report.sh
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-nginx-report.sh lessons/08-text-processing-grep-sed-awk/labs/sample/nginx_access.log
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-nginx-report.sh /var/log/nginx/access.log
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

file="${1:-/var/log/nginx/access.log}"
[[ -r "$file" ]] || { echo "No such log: $file" >&2; exit 1; }

awk '{
  if (match($0, /"([A-Z]+) ([^"]+) HTTP\/[0-9.]+"/, m)) {
    method=m[1]; path=m[2]
  } else next
  status=$9; ip=$1; total++; codes[status]++; hits[path]++; ips[ip]++
  if (status ~ /^[45]/) errs++
} END {
  printf "Total: %d\n", total
  printf "Error rate (4xx+5xx): %.2f%%\n", (total ? 100*errs/total : 0)
  printf "Status codes:\n"; for (c in codes) printf "  %s: %d\n", c, codes[c]
  printf "Top paths:\n"; for (p in hits) printf "  %s: %d\n", p, hits[p]
  printf "Unique IPs: %d\n", length(ips)+0
}' "$file"
