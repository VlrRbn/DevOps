#!/usr/bin/env bash

set -Eeuo pipefail
sudo nginx -t && sudo systemctl reload nginx && echo "Reload OK" || { echo "Config invalid"; exit 1; }
