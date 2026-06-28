#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

# Install nginx into the web AMI.
#
# The package check keeps the script idempotent for repeated Packer provisioner runs.
# Noninteractive mode avoids apt prompts in CI/build environments.
if ! dpkg -s nginx >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y nginx
fi

# Enable nginx so instances created from the AMI serve traffic automatically on boot. 
# The render-index service updates page content separately.
systemctl enable nginx
