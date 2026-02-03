#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

if systemctl list-unit-files | grep -q '^amazon-ssm-agent\.service'; then
  systemctl enable --now amazon-ssm-agent
  exit 0
fi

if command -v snap >/dev/null 2>&1; then
  if ! snap list amazon-ssm-agent >/dev/null 2>&1; then
    snap install amazon-ssm-agent --classic
  fi
  systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent
  exit 0
fi

apt-get update -y
apt-get install -y snapd
snap install amazon-ssm-agent --classic
systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent