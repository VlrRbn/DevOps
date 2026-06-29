#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

usage() {
  cat >&2 <<'USAGE'
Usage:
  post-incident-check.sh <dev|stage|prod>

Captures a post-incident Terraform plan and status marker.
It does not apply changes.
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
OUT_DIR="${OUT_DIR:-${LESSON_DIR}/evidence/post-incident-${ENV_NAME}-${STAMP}}"

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
terraform plan -detailed-exitcode -input=false -no-color > "${OUT_DIR}/post-incident-plan.txt" 2>&1
plan_ec=$?
set -e

echo "$plan_ec" > "${OUT_DIR}/post-incident-plan-exitcode.txt"

if [[ "$plan_ec" -eq 0 ]]; then
  status="CLEAN"
  exit_code=0
elif [[ "$plan_ec" -eq 2 ]]; then
  status="DRIFT_OR_DIFF"
  exit_code=2
else
  status="ERROR"
  exit_code=1
fi

cat > "${OUT_DIR}/post-incident-summary.txt" <<SUMMARY
environment=${ENV_NAME}
timestamp_utc=${STAMP}
terraform_root=${ROOT}
plan_exitcode=${plan_ec}
post_incident_status=${status}
script_exitcode=${exit_code}
SUMMARY

echo "POST_INCIDENT_STATUS=${status}"
echo "Post-incident check written to: $OUT_DIR"
exit "$exit_code"
