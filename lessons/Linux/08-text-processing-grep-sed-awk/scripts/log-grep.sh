#!/usr/bin/env bash
# Grep a pattern in a file or recursively in a directory.
# Usage: log-grep.sh <pattern> <file_or_dir> [grep-opts...]
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  log-grep.sh <pattern> <file_or_dir> [grep-opts...]

Examples:
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.sh "Failed password|Accepted password" /var/log/auth.log
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.sh "error|fail|critical" ./labs -i
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.sh "^PasswordAuthentication" labs/mock/sshd_config
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ $# -ge 2 ]] || { usage; exit 1; }
pattern="$1"
target="$2"
shift 2

if [[ -d "$target" ]]; then
  grep -rEn --color=always "$@" -e "$pattern" -- "$target"
else
  grep -nE --color=always "$@" -e "$pattern" -- "$target"
fi
