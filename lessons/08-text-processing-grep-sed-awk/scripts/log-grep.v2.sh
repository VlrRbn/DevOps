#!/usr/bin/env bash
# Grep in files/dirs or journalctl with optional unit/tag filters.
# Usage: log-grep.v2.sh <pattern> <file|dir|journal> [--unit UNIT] [--tag TAG] [--sshd-only] [-- <grep opts>]
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  log-grep.v2.sh <pattern> <file|dir|journal> [--unit UNIT] [--tag TAG] [--sshd-only] [-- <extra grep opts>]

Examples:
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.v2.sh "Failed password" journal --tag sshd
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.v2.sh "Accepted" journal --unit ssh.service
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.v2.sh "error|fail" ./labs -- -i
  ./lessons/08-text-processing-grep-sed-awk/scripts/log-grep.v2.sh "Failed password" journal --tag sshd --sshd-only
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ $# -ge 2 ]] || { usage; exit 1; }
pat="$1"
target="$2"
shift 2
unit=""
tag=""
sshd_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unit)      unit="${2:-}"; shift 2 ;;
    --tag)       tag="${2:-}"; shift 2 ;;
    --sshd-only) sshd_only=1; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

if [[ "$target" == "journal" ]]; then
  cmd=(journalctl -o cat --no-pager)
  [[ -n "$unit" ]] && cmd+=(-u "$unit")
  [[ -n "$tag" ]] && cmd+=(-t "$tag")
  "${cmd[@]}" | grep -nE "$@" -e "$pat" || true
else
  if [[ -d "$target" ]]; then
    grep -rEn "$@" -e "$pat" -- "$target" || true
  else
    grep -nE "$@" -e "$pat" -- "$target" || true
  fi
fi | {
  if (( sshd_only )); then
    grep -E 'sshd\[' || true
  else
    cat
  fi
}
