#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p /var/www/html

# Base template baked into AMI; placeholders are resolved at instance boot.
cat >/var/www/html/index.html <<'EOF'
<h1>Web baked by Packer</h1>
<p>BUILD_ID: __BUILD_ID__</p>
<p>Built At: __BUILD_TIME__</p>
<p>Hostname: __HOSTNAME__</p>
<p>InstanceId: __INSTANCE_ID__</p>
EOF
