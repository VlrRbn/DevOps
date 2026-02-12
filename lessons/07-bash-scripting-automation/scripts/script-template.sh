#!/usr/bin/env bash
# Description: Script template with strict mode, IFS, and error trap helper.
# Usage: copy and edit for new tools; update usage() and logic.
set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "ERR:$? at ${BASH_SOURCE[0]}:${LINENO}" >&2' ERR

usage() {
  echo "Usage: $0 ..."
}
