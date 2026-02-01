#!/usr/bin/env bash
# Description: Emit a simple timestamped log message to journald.
# Usage: hello.sh
# Output: Log entry tagged 'hello' with hostname and time.
echo "[hello] $(date '+%F %T') $(hostname)" | systemd-cat -t hello -p info
