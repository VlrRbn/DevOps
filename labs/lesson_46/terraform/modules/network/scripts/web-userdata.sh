#!/usr/bin/env bash
set -Eeuo pipefail

#--- Logging
LOG=/var/log/user-data.log
exec > >(tee -a "$LOG" | logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting user-data script at $(date -u)"

#--- Functions
has_internet() {
  timeout 2 bash -c 'cat < /dev/null > /dev/tcp/1.1.1.1/443' >/dev/null 2>&1
}

imds_token() {
  curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"
}

get_region() {
  local token
  token="$(imds_token || true)"
  if [[ -n "${token:-}" ]]; then
    curl -fsS -H "X-aws-ec2-metadata-token: $token" \
      http://169.254.169.254/latest/dynamic/instance-identity/document \
      | jq -r .region
  else
    echo "eu-west-1"
  fi
}

AWS_REGION="$(get_region)"
echo "Region: $AWS_REGION"

# --- Base packages install if internet is available
if has_internet; then
  echo "Internet: yes -> apt-get update/install"
  apt-get update -y
  apt-get install -y nginx curl ca-certificates jq
  echo "lab45 web: $(hostname) $(date -u)" > /var/www/html/index.html
  systemctl enable --now nginx
else
  echo "Internet: no -> skipping apt/curl/nginx install"
  # if nginx already exists, still write page and start it
  if command -v nginx >/dev/null 2>&1; then
    echo "lab45 web: $(hostname) $(date -u)" > /var/www/html/index.html || true
    systemctl enable --now nginx || true
  fi
fi

# Install SSM Agent (official.deb)
if has_internet; then
  echo "SSM agent service not found -> installing amazon-ssm-agent (official.deb) from regional S3"
  TMP="/tmp/amazon-ssm-agent.deb"
  curl -fsSL \
    "https://s3.${AWS_REGION}.amazonaws.com/amazon-ssm-${AWS_REGION}/latest/debian_amd64/amazon-ssm-agent.deb" -o "$TMP"
  dpkg -i "$TMP" || apt-get -f install -y

  systemctl enable --now amazon-ssm-agent
  systemctl status amazon-ssm-agent --no-pager || true
else
  echo "SSM agent not installed and has no internet."
fi

# Enable SSM Agent service if installed via official.deb
if systemctl list-unit-files | grep -q '^amazon-ssm-agent\.service'; then
  echo "SSM agent service found: amazon-ssm-agent"
  systemctl enable --now amazon-ssm-agent
  systemctl status amazon-ssm-agent --no-pager || true
  exit 0
fi

# Enable SSM Agent service if installed via snap
if systemctl list-unit-files | grep -q '^snap\.amazon-ssm-agent\.amazon-ssm-agent\.service'; then
  echo "SSM agent service found: snap.amazon-ssm-agent.amazon-ssm-agent"
  systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service
  systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service --no-pager || true
  exit 0
fi
