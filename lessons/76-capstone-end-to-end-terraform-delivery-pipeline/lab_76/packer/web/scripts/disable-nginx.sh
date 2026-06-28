#!/usr/bin/env bash
set -Eeuo pipefail

# BUILD_ID controls whether this image is intentionally broken.
#
# The lesson keeps the same Packer template but can produce different image variants.
# A build id ending in "-bad" creates an AMI where nginx is disabled so rollback/recovery drills
# have a realistic failure to detect.
build_id="${BUILD_ID:-}"

# Only disable nginx for intentionally broken AMIs.
#
# Masking prevents accidental service start after boot. That makes the failure
# deterministic for drills instead of depending on race conditions.
if [[ "$build_id" == *-bad ]]; then
  systemctl disable --now nginx
  systemctl mask nginx
  echo "[INFO] disabled nginx for bad build_id: $build_id"
else
  echo "[INFO] skip disabling nginx for build_id: ${build_id:-<empty>}"
fi
