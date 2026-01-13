#!/usr/bin/env bash
set -Eeuo pipefail

LOG=/var/log/user-data.log
exec > >(tee -a "$LOG" | logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting user-data script at $(date -u)"

# --- Base packages
apt-get update -y
apt-get install -y nginx curl ca-certificates jq

echo "lab44 web: $(hostname) $(date -u)" > /var/www/html/index.html
systemctl enable --now nginx

AWS_REGION="eu-west-1"

# Install SSM Agent (official.deb)
if ! command -v amazon-ssm-agent >/dev/null 2>&1; then
  echo "Installing amazon-ssm-agent (official deb)"
  TMP="/tmp/amazon-ssm-agent.deb"
  curl -fsSL \
    "https://s3.${AWS_REGION}.amazonaws.com/amazon-ssm-${AWS_REGION}/latest/debian_amd64/amazon-ssm-agent.deb" \
    -o "$TMP"

  dpkg -i "$TMP" || apt-get -f install -y
fi

echo "enabling amazon-ssm-agent"
systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || true

echo "amazon-ssm-agent status:"
systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service || true
