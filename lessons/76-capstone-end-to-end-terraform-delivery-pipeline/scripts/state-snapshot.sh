#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

usage() {
  cat >&2 <<'USAGE'
Usage:
  state-snapshot.sh <dev|stage|prod>

Creates a local evidence bundle before any Terraform recovery work.
It does not modify infrastructure or state.
USAGE
}

ENV_NAME="${1:-}"
case "$ENV_NAME" in
  dev|stage|prod) ;;
  *) usage; exit 64 ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LESSON_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ROOT="${LESSON_DIR}/lab_76/terraform/envs/${ENV_NAME}"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
OUT_DIR="${OUT_DIR:-${LESSON_DIR}/evidence/state-snapshot-${ENV_NAME}-${STAMP}}"

if [[ ! -d "$ROOT" ]]; then
  echo "Terraform root not found: $ROOT" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

cd "$ROOT"

terraform version > "${OUT_DIR}/terraform-version.txt" 2>&1
git rev-parse HEAD > "${OUT_DIR}/git-sha.txt" 2>&1 || true
git status --short > "${OUT_DIR}/git-status.txt" 2>&1 || true

set +e
terraform state pull > "${OUT_DIR}/terraform-state-pull.json" 2> "${OUT_DIR}/terraform-state-pull-stderr.txt"
state_pull_ec=$?
set -e

echo "$state_pull_ec" > "${OUT_DIR}/terraform-state-pull-exitcode.txt"

set +e
terraform plan -detailed-exitcode -input=false -no-color > "${OUT_DIR}/current-plan.txt" 2>&1
plan_ec=$?
set -e

echo "$plan_ec" > "${OUT_DIR}/current-plan-exitcode.txt"

cat > "${OUT_DIR}/snapshot-summary.txt" <<SUMMARY
environment=${ENV_NAME}
timestamp_utc=${STAMP}
terraform_root=${ROOT}
state_pull_exitcode=${state_pull_ec}
plan_exitcode=${plan_ec}
SUMMARY

echo "Snapshot written to: $OUT_DIR"

if [[ "$state_pull_ec" -ne 0 ]]; then
  echo "WARNING: terraform state pull failed; evidence was still written to ${OUT_DIR}" >&2
fi

if [[ "$plan_ec" -eq 1 ]]; then
  echo "WARNING: terraform plan failed; evidence was still written to ${OUT_DIR}" >&2
fi

if [[ "$state_pull_ec" -ne 0 || "$plan_ec" -eq 1 ]]; then
  exit 1
fi
