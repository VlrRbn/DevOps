#!/usr/bin/env bash
set -Eeuo pipefail

# IMDSv2 token
TOKEN="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)"

HN="$(hostname)"
IID="unknown"
AMI_VERSION="unknown"
BUILD_TIME="unknown"

if [[ -n "${TOKEN:-}" ]]; then
  IID="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || true)"
fi

if [[ -f /etc/web-build/meta.env ]]; then
  # shellcheck disable=SC1091
  source /etc/web-build/meta.env
fi

sed -i \
  -e "s/__AMI_VERSION__/${AMI_VERSION}/g" \
  -e "s/__BUILD_TIME__/${BUILD_TIME}/g" \
  -e "s/__HOSTNAME__/${HN}/g" \
  -e "s/__INSTANCE_ID__/${IID}/g" \
  /var/www/html/index.html