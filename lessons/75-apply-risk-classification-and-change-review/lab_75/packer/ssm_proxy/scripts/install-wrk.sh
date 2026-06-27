#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

# BUILD_ID is passed by Packer. The lab uses a naming convention where images
# ending in "-wrk" are dedicated load-generator/probe images.
build_id="${BUILD_ID:-}"

# Install wrk only for dedicated load-generator AMIs.
if [[ "$build_id" == *-wrk ]]; then
  apt-get update -y
  apt-get install -y wrk
  echo "[INFO] installed wrk for build_id: $build_id"
else
  echo "[INFO] skip wrk install for build_id: ${build_id:-<empty>}"
fi
