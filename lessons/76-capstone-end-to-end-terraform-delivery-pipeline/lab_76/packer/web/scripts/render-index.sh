#!/usr/bin/env bash
set -Eeuo pipefail

# Render the nginx index page with runtime metadata.
#
# Packer bakes a template into the AMI, but some values are known only after an EC2 instance
# boots: hostname and instance ID. This script runs at boot through render-index.service and
# writes the final /var/www/html/index.html.

# Fetch an IMDSv2 token. If metadata is unavailable, the script continues with
# safe fallback values so nginx can still serve a page.
TOKEN="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)"

HN="$(hostname)"
IID="unknown"
BUILD_ID="unknown"
BUILD_TIME="unknown"

# Render from an immutable template to keep reruns idempotent. Re-running the
# service should not replace already rendered values inside the current index.
TEMPLATE="/etc/web-build/index.template"
OUTPUT="/var/www/html/index.html"

# Instance ID is runtime metadata; it cannot be baked into the AMI.
if [[ -n "${TOKEN:-}" ]]; then
  IID="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || true)"
fi

if [[ -f /etc/web-build/build_id ]]; then
  # BUILD_ID is baked during AMI build and identifies rollout version.
  BUILD_ID="$(tr -d '\n' </etc/web-build/build_id)"
fi

if [[ -f /etc/web-build/build_time ]]; then
  # BUILD_TIME is baked during AMI build and helps prove which AMI generation is currently serving traffic.
  BUILD_TIME="$(tr -d '\n' </etc/web-build/build_time)"
fi

if [[ ! -f "${TEMPLATE}" ]]; then
  # Fallback for old images: bootstrap template from current index.html once.
  # This keeps the service compatible if a previous AMI did not create /etc/web-build/index.template.
  cp "${OUTPUT}" "${TEMPLATE}"
fi

# Escape values so sed replacement is safe for '/', '&', and backslashes.
escape_sed() {
  printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'
}

tmp_file="$(mktemp)"

# Render into a temp file first, then publish atomically with install. This avoids partially written
# index.html if the script is interrupted.
sed \
  -e "s/__BUILD_ID__/$(escape_sed "${BUILD_ID}")/g" \
  -e "s/__BUILD_TIME__/$(escape_sed "${BUILD_TIME}")/g" \
  -e "s/__HOSTNAME__/$(escape_sed "${HN}")/g" \
  -e "s/__INSTANCE_ID__/$(escape_sed "${IID}")/g" \
  "${TEMPLATE}" >"${tmp_file}"

install -m 0644 "${tmp_file}" "${OUTPUT}"
rm -f "${tmp_file}"
