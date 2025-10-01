#!/usr/bin/env bash
set -Eeuo pipefail

site="${1:?site name, e.g., lab13}"
src="/etc/nginx/sites-available/${site}_v2.conf"
dst="/etc/nginx/sites-enabled/${site}.conf"

sudo nginx -t || true
[[ -f "$src" ]] || { echo "No $src"; exit 1; }
sudo ln -sfn "$src" "$dst"
sudo nginx -t && sudo systemctl reload nginx && echo "Deployed ${site}_v2 || { echo "Invalid config"; exit 1; }
