#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

if ! dpkg -s nginx >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y nginx
fi

systemctl enable nginx