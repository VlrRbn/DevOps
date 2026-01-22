#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p /var/www/html

cat >/var/www/html/index.html <<'EOF'
<h1>Web baked by Packer</h1>
<p>Hostname: __HOSTNAME__</p>
<p>InstanceId: __INSTANCE_ID__</p>
EOF