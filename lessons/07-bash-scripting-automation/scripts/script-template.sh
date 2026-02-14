#!/usr/bin/env bash
# Description: Script template with strict mode, IFS, and error trap helper.
# Usage: copy and edit for new tools; update usage() and logic.
set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "ERR:$? at ${BASH_SOURCE[0]}:${LINENO}" >&2' ERR

usage() {
  cat <<'USAGE'
Usage:
  script-template.sh ...

Examples:
  cp lessons/07-bash-scripting-automation/scripts/script-template.sh ./my-tool.sh
  chmod +x ./my-tool.sh
  ./my-tool.sh --help
USAGE
}
