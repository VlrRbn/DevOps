#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  module-release-note.sh <module> <version> <previous-ref> <new-ref> [patch|minor|major]

Example:
  module-release-note.sh network v1.1.0 network/v1.0.0 HEAD minor
USAGE
}

MODULE="${1:-}"
VERSION="${2:-}"
PREVIOUS_REF="${3:-}"
NEW_REF="${4:-}"
RELEASE_TYPE="${5:-}"

if [[ -z "$MODULE" || -z "$VERSION" || -z "$PREVIOUS_REF" || -z "$NEW_REF" ]]; then
  usage
  exit 64
fi

if [[ -n "$RELEASE_TYPE" && ! "$RELEASE_TYPE" =~ ^(patch|minor|major)$ ]]; then
  echo "release type must be one of: patch, minor, major" >&2
  exit 64
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

MODULE_PATH="lessons/72-module-versioning-and-release-discipline/lab_72/terraform/modules/${MODULE}"

if [[ ! -d "$MODULE_PATH" ]]; then
  echo "module path not found: ${MODULE_PATH}" >&2
  exit 1
fi

for ref in "$PREVIOUS_REF" "$NEW_REF"; do
  if ! git rev-parse --verify "${ref}^{commit}" >/dev/null 2>&1; then
    echo "Git ref does not resolve to a commit: ${ref}" >&2
    exit 2
  fi
done

cat <<HEADER
# ${MODULE}/${VERSION}

## Comparison

- Previous ref: ${PREVIOUS_REF}
- New ref: ${NEW_REF}
- Module path: ${MODULE_PATH}

## Changed files

HEADER

git diff --name-status "${PREVIOUS_REF}" "${NEW_REF}" -- "${MODULE_PATH}" || true

cat <<'BODY'

## Interface changes to review

BODY

git diff --unified=0 "${PREVIOUS_REF}" "${NEW_REF}" -- \
  "${MODULE_PATH}/variables.tf" \
  "${MODULE_PATH}/outputs.tf" \
  "${MODULE_PATH}/versions.tf" || true

cat <<FOOTER

## Release decision

- Version type: ${RELEASE_TYPE:-patch / minor / major}
- Breaking change: yes / no
- Caller action required:
- Contract tests passed:
- Policy tests passed:
- Rollback target:
- Promotion path: dev -> stage -> prod

## Notes

Do not move an existing published tag. If the release note is wrong after publishing, create a corrected release version.
FOOTER
