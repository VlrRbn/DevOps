#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  check-module-version.sh <env-root> <expected-ref> [--allow-local]

Checks that an env root pins the network module source to the expected Git ref.
Use --allow-local only for the pre-release lab baseline where roots still use ../../modules/network.
USAGE
}

ROOT="${1:-}"
EXPECTED_REF="${2:-}"
ALLOW_LOCAL="${3:-}"

if [[ -z "$ROOT" || -z "$EXPECTED_REF" ]]; then
  usage
  exit 64
fi

if [[ "$ALLOW_LOCAL" != "" && "$ALLOW_LOCAL" != "--allow-local" ]]; then
  usage
  exit 64
fi

MAIN_TF="${ROOT}/main.tf"

if [[ ! -f "$MAIN_TF" ]]; then
  echo "main.tf not found: $MAIN_TF" >&2
  exit 1
fi

source_lines="$(grep -n 'source[[:space:]]*=' "$MAIN_TF" || true)"

if grep -Fq 'source = "../../modules/network"' "$MAIN_TF"; then
  if [[ "$ALLOW_LOCAL" == "--allow-local" ]]; then
    echo "module source is local for lab baseline: ${ROOT}"
    exit 0
  fi

  echo "module source is still local: ${ROOT}" >&2
  echo "expected pinned ref: ${EXPECTED_REF}" >&2
  echo "replace local source with a Git source using ?ref=${EXPECTED_REF}" >&2
  exit 2
fi

if ! grep -Fq "ref=${EXPECTED_REF}" "$MAIN_TF"; then
  echo "expected module ref not found" >&2
  echo "root: ${ROOT}" >&2
  echo "expected ref: ${EXPECTED_REF}" >&2
  echo >&2
  echo "$source_lines" >&2
  exit 3
fi

echo "module ref ok: ${ROOT} -> ${EXPECTED_REF}"
