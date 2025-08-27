#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "ERR:$? at ${BASH_SOURCE[0]}:${LINENO}" >&2' ERR
usage(){ echo "Usage: $0 ..."; }
