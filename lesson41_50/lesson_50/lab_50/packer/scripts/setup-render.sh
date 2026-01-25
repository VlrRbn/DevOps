#!/usr/bin/env bash
set -Eeuo pipefail

AMI_VERSION="${AMI_VERSION:-unknown}"
BUILD_TIME="${BUILD_TIME:-unknown}"

sudo mkdir -p /etc/web-build
sudo install -d -m 0755 /usr/local/bin
sudo install -m 0755 /tmp/render-index.sh /usr/local/bin/render-index.sh
sudo install -m 0644 /tmp/render-index.service /etc/systemd/system/render-index.service
echo "AMI_VERSION=${AMI_VERSION}" | sudo tee /etc/web-build/meta.env >/dev/null
echo "BUILD_TIME=${BUILD_TIME}" | sudo tee -a /etc/web-build/meta.env >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable render-index.service