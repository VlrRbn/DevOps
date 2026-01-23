#!/usr/bin/env bash
set -e

# REGION variable
REGION="eu-west-1"

# Update and install nginx
apt-get update -y
apt-get install -y nginx

# Enable and start nginx
systemctl enable nginx
systemctl start nginx

# Ensure SSM agent is running (usually already installed)
systemctl enable amazon-ssm-agent || true
systemctl start amazon-ssm-agent || true

TOKEN="$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")"
echo "web OK: $(hostname) $(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id || true)" > /var/www/html/index.html
