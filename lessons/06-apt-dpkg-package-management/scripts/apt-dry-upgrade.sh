#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  apt-dry-upgrade.sh [--full]

Examples:
  ./lessons/06-apt-dpkg-package-management/scripts/apt-dry-upgrade.sh
  ./lessons/06-apt-dpkg-package-management/scripts/apt-dry-upgrade.sh --full
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

MODE="upgrade"
if [[ "${1:-}" == "--full" ]]; then
  MODE="full-upgrade"
elif [[ -n "${1:-}" ]]; then
  usage
  exit 2
fi

echo "[INFO] refreshing package index"
sudo apt update

echo "[INFO] simulating apt-get -s $MODE"
sudo apt-get -s "$MODE"
