#!/usr/bin/env bash
# Report top SSH failed login source IPs from auth.log or journald.
# Usage: log-ssh-fail-report.sh [journal|auth]
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  log-ssh-fail-report.sh [journal|auth]

Examples:
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-ssh-fail-report.sh
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-ssh-fail-report.sh journal
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-ssh-fail-report.sh auth
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

src="${1:-journal}"
if [[ "$src" != "journal" && "$src" != "auth" ]]; then
  usage
  exit 1
fi

if [[ "$src" == "auth" && -f /var/log/auth.log ]]; then
  sudo zgrep -hE "Failed password" /var/log/auth.log* 2>/dev/null || true
else
  sudo journalctl -t sshd --since "today" -o cat 2>/dev/null |
    grep -E "Failed password|Invalid user|Disconnected from invalid user" || true
fi |
  awk '{for(i=1;i<=NF;i++) if ($i=="from") {ip=$(i+1); gsub(/^[\[\(]+|[\]\),;]+$/,"",ip); print ip; break}}' |
  sort | uniq -c | sort -nr | head -10
