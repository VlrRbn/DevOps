#!/usr/bin/env bash
set -Eeuo pipefail

# IMDSv2 token
TOKEN="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)"

HN="$(hostname)"
IID="unknown"
BUILD_ID="unknown"
BUILD_TIME="unknown"
# Render from template to keep reruns idempotent.
TEMPLATE="/etc/web-build/index.template"
OUTPUT="/var/www/html/index.html"

if [[ -n "${TOKEN:-}" ]]; then
  IID="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || true)"
fi

if [[ -f /etc/web-build/build_id ]]; then
  # BUILD_ID is baked during AMI build and identifies rollout version.
  BUILD_ID="$(tr -d '\n' </etc/web-build/build_id)"
fi

if [[ -f /etc/web-build/build_time ]]; then
  BUILD_TIME="$(tr -d '\n' </etc/web-build/build_time)"
fi

if [[ ! -f "${TEMPLATE}" ]]; then
  # Fallback for old images: bootstrap template from current index.html once.
  cp "${OUTPUT}" "${TEMPLATE}"
fi

# Escape values so sed replacement is safe for '/', '&', and backslashes.
escape_sed() {
  printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'
}

tmp_file="$(mktemp)"
# Render into temp file first; publish with install.
sed \
  -e "s/__BUILD_ID__/$(escape_sed "${BUILD_ID}")/g" \
  -e "s/__BUILD_TIME__/$(escape_sed "${BUILD_TIME}")/g" \
  -e "s/__HOSTNAME__/$(escape_sed "${HN}")/g" \
  -e "s/__INSTANCE_ID__/$(escape_sed "${IID}")/g" \
  "${TEMPLATE}" >"${tmp_file}"

install -m 0644 "${tmp_file}" "${OUTPUT}"
rm -f "${tmp_file}"
