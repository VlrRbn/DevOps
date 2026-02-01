#!/usr/bin/env bash
# Description: Test nginx config and reload only if validation succeeds.
# Usage: nginx-reload-safe.sh
# Output: 'Reload OK' or error message.

set -Eeuo pipefail
sudo nginx -t && sudo systemctl reload nginx && echo "Reload OK" || { echo "Config invalid"; exit 1; }
