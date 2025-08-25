#!/usr/bin/env bash
echo "[hello] $(date '+%F %T') $(hostname)" | systemd-cat -t hello -p info
