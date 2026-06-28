#!/usr/bin/env bash
set -Eeuo pipefail

# Generate a Markdown reviewer note from risk-decision.json.
#
# This does not approve anything. It produces a review template that captures the key fields
# a human should read before approving a real apply pipeline.

usage() {
  cat >&2 <<'USAGE'
Usage:
  reviewer-note-template.sh <risk-decision.json>
USAGE
}

RISK_JSON="${1:-}"

if [[ -z "$RISK_JSON" ]]; then
  usage
  exit 64
fi

if [[ ! -f "$RISK_JSON" ]]; then
  echo "risk decision JSON not found: $RISK_JSON" >&2
  exit 1
fi

if ! jq -e 'type == "object" and (.risk | type == "string") and (.apply_allowed | type == "boolean")' "$RISK_JSON" >/dev/null; then
  echo "invalid risk-decision.json shape: $RISK_JSON" >&2
  exit 64
fi

target_env="$(jq -r '.target_env // "unknown"' "$RISK_JSON")"
release_id="$(jq -r '.release_id // ""' "$RISK_JSON")"
source_env="$(jq -r '.source_env // ""' "$RISK_JSON")"
risk="$(jq -r '.risk' "$RISK_JSON")"
apply_allowed="$(jq -r '.apply_allowed' "$RISK_JSON")"
approval_required="$(jq -r '.approval_required // "unknown"' "$RISK_JSON")"
approval_level="$(jq -r '.approval_level // "unknown"' "$RISK_JSON")"
reason_codes="$(jq -r '(.reason_codes // []) | join(", ")' "$RISK_JSON")"

cat <<NOTE
# Change Review

- Commit SHA:
- Target environment: ${target_env}
- Release ID: ${release_id:-n/a}
- Source environment: ${source_env:-n/a}
- Risk level: ${risk}
- Apply allowed by risk gate: ${apply_allowed}
- Approval required: ${approval_required}
- Approval level: ${approval_level}
- Reason codes: ${reason_codes:-n/a}
- Security policy result:
- Cost policy result:
- Promotion evidence:
- Incident mode:
- Approval decision: approve / reject / request changes
- Reviewer:
- Reviewed at UTC:

## Reviewer Notes

-
NOTE
