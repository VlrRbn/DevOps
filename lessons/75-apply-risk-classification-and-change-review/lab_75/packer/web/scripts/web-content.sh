#!/usr/bin/env bash
set -Eeuo pipefail

# Create the base nginx document root during AMI build.
#
# The file intentionally contains placeholders instead of final values. Runtime
# metadata such as instance ID is unavailable during Packer build, so
# render-index.service replaces placeholders after EC2 boot.
mkdir -p /var/www/html

# Base template baked into AMI; placeholders are resolved at instance boot.
cat >/var/www/html/index.html <<'EOF'
<h1>Web baked by Packer</h1>
<p>BUILD_ID: __BUILD_ID__</p>
<p>Built At: __BUILD_TIME__</p>
<p>Hostname: __HOSTNAME__</p>
<p>InstanceId: __INSTANCE_ID__</p>
EOF
