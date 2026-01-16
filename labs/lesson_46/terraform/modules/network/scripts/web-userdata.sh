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
