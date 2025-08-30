#!/usr/bin/env bash
set -Eeuo pipefail
src="${1:-journal}"
if [[ "$src" == "auth" && -f /var/log/auth.log ]]; then
sudo zgrep -hE "Failed password" /var/log/auth.log* || true
else
sudo journalctl -t sshd --since "today" -o cat 2>/dev/null | grep -E "Failed password|Invalid user|Disconnected from invalid user" || true
fi | awk '{for(i=1;i<=NF;i++) if ($i=="from") {ip=$(i+1); gsub(/^[\[\(]+|[\]\),;]+$/,"",ip); print ip; break}}' | sort | uniq -c | sort -nr | head -10
