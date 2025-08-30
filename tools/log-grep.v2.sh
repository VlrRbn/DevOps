#!/usr/bin/env bash
set -Eeuo pipefail
usage(){ echo "Usage: $0 <pattern> <file|dir|journal> [--unit UNIT] [--tag TAG] [--sshd-only] [-- <extra grep opts>]"; }
[[ $# -ge 2 ]] || { usage; exit 1; }
pat="$1"; target="$2"; shift 2
unit=""; tag=""; sshd_only=0
while [[ $# -gt 0 ]]; do
case "$1" in
 --unit)      unit="${2:-}"; shift 2;;
 --tag)       tag="${2:-}"; shift 2;;
 --sshd-only) sshd_only=1; shift;;
 --) shift; break;;
 *) break;;
esac
done
if [[ "$target" == "journal" ]]; then
cmd=(journalctl -o cat --no-pager)
[[ -n "$unit" ]] && cmd+=(-u "$unit")
[[ -n "$tag"  ]] && cmd+=(-t "$tag")
"${cmd[@]}" | grep -nE "$@" -e "$pat" || true
else
if [[ -d "$target" ]]; then
grep -rEn "$@" -e "$pat" -- "$target" || true
else
grep -nE  "$@" -e "$pat" -- "$target" || true
fi
fi | { if (( sshd_only )); then grep -E 'sshd\[' || true; else cat; fi; }
