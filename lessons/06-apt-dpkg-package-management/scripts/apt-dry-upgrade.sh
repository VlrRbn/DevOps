#!/usr/bin/env bash
set -euo pipefail

MODE="upgrade"
if [[ "${1:-}" == "--full" ]]; then
  MODE="full-upgrade"
fi

echo "[INFO] refreshing package index"
sudo apt update

echo "[INFO] simulating apt-get -s $MODE"
sudo apt-get -s "$MODE"
