#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

usage() {
  cat >&2 <<'USAGE'
Usage:
  collect-capstone-proof.sh <dev|stage|prod> [source-dir]

Creates a timestamped capstone evidence directory and copies known review/apply/runtime files into it.
It does not run Terraform, call AWS, apply, destroy, restore, or delete anything.

Arguments:
  env         Target environment.
  source-dir Optional directory to copy evidence from. Defaults to the Terraform env root.

Environment variables:
  OUT_ROOT    Parent directory for evidence. Default: <lesson>/evidence
  RELEASE_ID  Optional release/change id used in the output folder name.
USAGE
}

ENV_NAME="${1:-}"
SOURCE_DIR_ARG="${2:-}"
case "$ENV_NAME" in
  dev|stage|prod) ;;
  *) usage; exit 64 ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LESSON_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_SOURCE_DIR="${LESSON_DIR}/lab_76/terraform/envs/${ENV_NAME}"
SOURCE_DIR="${SOURCE_DIR_ARG:-$DEFAULT_SOURCE_DIR}"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
RELEASE_ID="${RELEASE_ID:-manual}"
OUT_ROOT="${OUT_ROOT:-${LESSON_DIR}/evidence}"
OUT_DIR="${OUT_ROOT}/l76-${ENV_NAME}-${RELEASE_ID}-${STAMP}"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

copy_if_exists() {
  local src="$1"
  local dst_name="${2:-$(basename "$src")}"
  if [[ -e "$src" ]]; then
    cp -a "$src" "$OUT_DIR/$dst_name"
    printf '%s\n' "$dst_name" >> "$OUT_DIR/copied-files.txt"
  fi
}

write_command_output() {
  local name="$1"
  shift
  set +e
  "$@" > "$OUT_DIR/${name}.txt" 2>&1
  local ec=$?
  set -e
  printf '%s\n' "$ec" > "$OUT_DIR/${name}-exitcode.txt"
}

# Metadata.
printf '%s\n' "$ENV_NAME" > "$OUT_DIR/target-env.txt"
printf '%s\n' "$RELEASE_ID" > "$OUT_DIR/release-id.txt"
printf '%s\n' "$STAMP" > "$OUT_DIR/collected-at-utc.txt"
printf '%s\n' "$SOURCE_DIR" > "$OUT_DIR/source-dir.txt"
write_command_output git-sha git rev-parse HEAD
write_command_output git-status git status --short
write_command_output terraform-version terraform version

# Common files produced by the manual flow or CI artifact download.
for file in \
  tfplan tfplan.sha256 tfplan.txt tfplan.json \
  apply.txt applied-tfplan-sha256.txt \
  post_apply_plan.txt post_apply_exitcode.txt \
  promotion-evidence.json promotion-manifest.json \
  reviewer-note.md capstone-review-summary.md; do
  copy_if_exists "$SOURCE_DIR/$file"
done

# Common output directories from policy/risk/runtime steps.
for dir in policy-results cost-policy-results risk-results review-artifact runtime-health post-incident state-snapshot; do
  copy_if_exists "$SOURCE_DIR/$dir"
done

# Copy matching evidence files from source dir root if user used custom names.
find "$SOURCE_DIR" -maxdepth 1 -type f \
  \( -name '*decision*.txt' -o -name '*decision*.md' -o -name '*decision*.json' -o -name '*summary*.txt' -o -name '*summary*.md' -o -name '*summary*.json' \) \
  -print0 | while IFS= read -r -d '' file; do
    copy_if_exists "$file"
  done

cat > "$OUT_DIR/evidence-manifest.txt" <<MANIFEST
environment=${ENV_NAME}
release_id=${RELEASE_ID}
source_dir=${SOURCE_DIR}
out_dir=${OUT_DIR}
collected_at_utc=${STAMP}
MANIFEST

if [[ ! -s "$OUT_DIR/copied-files.txt" ]]; then
  echo "No known evidence files were copied. Metadata was still written." > "$OUT_DIR/copied-files.txt"
fi

echo "Evidence collected to: $OUT_DIR"
