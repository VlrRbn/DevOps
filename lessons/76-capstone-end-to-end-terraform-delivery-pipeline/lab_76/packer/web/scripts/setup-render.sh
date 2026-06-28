#!/usr/bin/env bash
set -Eeuo pipefail

# Packer passes these values during image build. They become part of the visible
# web page so rollout/recovery drills can prove which AMI build is running.
BUILD_ID="${BUILD_ID:-unknown}"
BUILD_TIME="${BUILD_TIME:-unknown}"

# Prepare runtime metadata and renderer for boot-time page generation.
sudo mkdir -p /etc/web-build
sudo install -d -m 0755 /usr/local/bin
sudo install -m 0755 /tmp/render-index.sh /usr/local/bin/render-index.sh
sudo install -m 0644 /tmp/render-index.service /etc/systemd/system/render-index.service

# Build identity baked into AMI.
echo "${BUILD_ID}" | sudo tee /etc/web-build/build_id >/dev/null
echo "${BUILD_TIME}" | sudo tee /etc/web-build/build_time >/dev/null

# Keep an immutable template with placeholders.
sudo cp /var/www/html/index.html /etc/web-build/index.template

# Register and enable the one-shot renderer so every instance boot refreshes hostname/instance-id values.
sudo systemctl daemon-reload
sudo systemctl enable render-index.service
