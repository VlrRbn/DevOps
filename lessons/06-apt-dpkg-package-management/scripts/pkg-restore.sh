#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  pkg-restore.sh [--apply] <packages.list>

Description:
  Restores package selections from packages.list.
  Default mode is simulation.

Options:
  --apply --- perform real dselect-upgrade (without this flag: simulate)

Examples:
  ./lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh ./pkg-state/packages.list
  ./lessons/06-apt-dpkg-package-management/scripts/pkg-restore.sh --apply ./pkg-state/packages.list
USAGE
}

APPLY=0
LIST_FILE=""

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --apply)
      APPLY=1
      ;;
    *)
      if [[ -z "$LIST_FILE" ]]; then
        LIST_FILE="$arg"
      else
        echo "ERROR: multiple list files provided" >&2
        usage
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$LIST_FILE" ]]; then
  echo "ERROR: <packages.list> is required" >&2
  usage
  exit 2
fi

if [[ ! -f "$LIST_FILE" ]]; then
  echo "ERROR: file not found: $LIST_FILE" >&2
  exit 1
fi

echo "[INFO] refreshing package index"
sudo apt update

if [[ "$APPLY" -eq 1 ]]; then
  echo "[INFO] APPLY mode: setting selections and running real dselect-upgrade"
  sudo dpkg --set-selections < "$LIST_FILE"
  sudo apt-get -y dselect-upgrade
  echo "[OK] restore applied"
  exit 0
fi

TMP_CURRENT="$(mktemp)"
cleanup() {
  rm -f "$TMP_CURRENT"
}
trap cleanup EXIT

dpkg --get-selections > "$TMP_CURRENT"

echo "[INFO] SIMULATE mode: temporarily applying selections"
sudo dpkg --set-selections < "$LIST_FILE"
sudo apt-get -s dselect-upgrade

echo "[INFO] restoring original selections after simulation"
sudo dpkg --set-selections < "$TMP_CURRENT"

echo "[OK] simulation completed, real state preserved"
