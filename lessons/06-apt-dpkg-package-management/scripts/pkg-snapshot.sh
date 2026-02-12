#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage:
  pkg-snapshot.sh [output_dir]

Description:
  Saves package state snapshot:
  - packages.list (dpkg selections)
  - packages_table.txt (human-readable table)
USAGE
  exit 0
fi

OUT_DIR="${1:-./pkg-state_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

dpkg --get-selections > "$OUT_DIR/packages.list"
dpkg -l > "$OUT_DIR/packages_table.txt"

echo "[OK] snapshot saved"
echo "  - $OUT_DIR/packages.list"
echo "  - $OUT_DIR/packages_table.txt"
