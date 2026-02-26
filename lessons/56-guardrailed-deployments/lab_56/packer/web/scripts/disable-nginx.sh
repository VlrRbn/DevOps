#!/usr/bin/env bash
set -Eeuo pipefail

systemctl disable --now nginx
systemctl mask nginx