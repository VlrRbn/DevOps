#!/usr/bin/env bash
# Emit a timestamped log line to journald with tag "hello".
set -euo pipefail

echo "[hello] $(date '+%F %T') $(hostname)" | systemd-cat -t hello -p info
