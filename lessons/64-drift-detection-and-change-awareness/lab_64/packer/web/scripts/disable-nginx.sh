#!/usr/bin/env bash
set -Eeuo pipefail

build_id="${BUILD_ID:-}"

# Only disable nginx for intentionally broken AMIs (for rollback drills).
if [[ "$build_id" == *-bad ]]; then
  systemctl disable --now nginx
  systemctl mask nginx
  echo "[INFO] disabled nginx for bad build_id: $build_id"
else
  echo "[INFO] skip disabling nginx for build_id: ${build_id:-<empty>}"
fi
