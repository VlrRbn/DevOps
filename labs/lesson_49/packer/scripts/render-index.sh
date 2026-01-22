#!/usr/bin/env bash
set -Eeuo pipefail

# IMDSv2 token
TOKEN="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)"

IID="unknown"

if [[ -n "${TOKEN:-}" ]]; then
  IID="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || true)"
fi

HN="$(hostname)"

sed -i \
  -e "s/__HOSTNAME__/${HN}/g" \
  -e "s/__INSTANCE_ID__/${IID}/g" \
  /var/www/html/index.html