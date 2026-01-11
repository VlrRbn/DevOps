#!/usr/bin/env bash
set -Eeuo pipefail

apt-get update -y
apt-get install -y nginx

echo "lab44 web: $(hostname) $(date -u)" > /var/www/html/index.html
systemctl enable --now nginx
