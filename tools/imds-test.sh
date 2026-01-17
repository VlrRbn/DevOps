#!/usr/bin/env bash
set -euo pipefail

echo "[1] IMDSv1-style request (no token) should be 401"
curl -sS -o /dev/null -w "code=%{http_code}\n" http://169.254.169.254/latest/meta-data/

echo "[2] Get IMDSv2 token"
TOKEN="$(curl -sS -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")"

echo "[3] IMDSv2 request should be 200"
curl -sS -o /dev/null -w "code=%{http_code}\n" \
  -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/

echo "[4] instance-id:"
curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id
echo
