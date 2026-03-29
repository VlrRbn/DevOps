#!/usr/bin/env bash
set -Eeuo pipefail

BUILD_ID="${BUILD_ID:-unknown}"
BUILD_TIME="${BUILD_TIME:-unknown}"

# Prepare runtime metadata and renderer for boot-time page generation.
sudo mkdir -p /etc/web-build
sudo install -d -m 0755 /usr/local/bin
sudo install -m 0755 /tmp/render-index.sh /usr/local/bin/render-index.sh
sudo install -m 0644 /tmp/render-index.service /etc/systemd/system/render-index.service
# Build identity baked into AMI (deployment contract: visible BUILD_ID).
echo "${BUILD_ID}" | sudo tee /etc/web-build/build_id >/dev/null
echo "${BUILD_TIME}" | sudo tee /etc/web-build/build_time >/dev/null
# Keep immutable template with placeholders; service will render final index at boot.
sudo cp /var/www/html/index.html /etc/web-build/index.template
sudo systemctl daemon-reload
sudo systemctl enable render-index.service
