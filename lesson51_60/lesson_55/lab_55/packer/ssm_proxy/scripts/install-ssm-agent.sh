#!/usr/bin/env bash
# Why this script was changed and why this script uses deb and not snap:
# SSM proxy was flapping (TargetNotConnected / ConnectionLost). In this lab,
# snap-based agent lifecycle was unstable after AMI clone/boot. We install
# amazon-ssm-agent from regional deb package and clean registration state
# before AMI snapshot so each new instance registers as fresh.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

# Detect instance region via IMDSv2 to build correct regional S3 URL.
imds_region() {
  local token
  token="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)"
  if [[ -z "${token}" ]]; then
    return 1
  fi

  curl -fsS -H "X-aws-ec2-metadata-token: ${token}" \
    "http://169.254.169.254/latest/dynamic/instance-identity/document" |
    sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

install_restart_policy() {
  mkdir -p /etc/systemd/system/amazon-ssm-agent.service.d
  cat >/etc/systemd/system/amazon-ssm-agent.service.d/restart.conf <<'EOF'
[Service]
Restart=always
RestartSec=5
EOF
  systemctl daemon-reload
}

# Remove snap variant if present; deb installer refuses coexistence.
if command -v snap >/dev/null 2>&1 && snap list amazon-ssm-agent >/dev/null 2>&1; then
  snap stop amazon-ssm-agent || true
  systemctl stop snap.amazon-ssm-agent.amazon-ssm-agent.service 2>/dev/null || true
  for _ in 1 2 3; do
    if snap remove --purge amazon-ssm-agent; then
      break
    fi
    sleep 2
  done
fi

if ! systemctl list-unit-files | grep -q '^amazon-ssm-agent\.service'; then
  REGION="${AWS_REGION:-$(imds_region || true)}"
  REGION="${REGION:-eu-west-1}"

  apt-get update -y
  apt-get install -y curl ca-certificates

  SSM_DEB_URL="https://s3.${REGION}.amazonaws.com/amazon-ssm-${REGION}/latest/debian_amd64/amazon-ssm-agent.deb"
  curl -fL "${SSM_DEB_URL}" -o /tmp/amazon-ssm-agent.deb
  dpkg -i /tmp/amazon-ssm-agent.deb || apt-get install -f -y
  rm -f /tmp/amazon-ssm-agent.deb
fi

install_restart_policy
systemctl enable --now amazon-ssm-agent
systemctl restart amazon-ssm-agent || true

# AMI hygiene: do not bake instance-specific registration artifacts.
systemctl stop amazon-ssm-agent || true
rm -rf /var/lib/amazon/ssm/* || true
rm -rf /var/log/amazon/ssm/* || true
mkdir -p /var/lib/amazon/ssm /var/log/amazon/ssm
systemctl enable amazon-ssm-agent
