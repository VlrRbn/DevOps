#!/usr/bin/env bash
set -Eeuo pipefail

INCIDENT_ID="${1:-INCIDENT-ID}"
ENV_NAME="${2:-dev}"

cat <<TEMPLATE
# Terraform Incident Decision

- Incident ID: ${INCIDENT_ID}
- Environment: ${ENV_NAME}
- Date UTC:
- Commit SHA:
- Terraform version:
- Operator:
- Reviewer:
- Severity:
- Status: open/closed

## Symptom

-

## Immediate Actions

- [ ] Applies frozen
- [ ] Current state snapshotted
- [ ] Current plan captured
- [ ] AWS reality checked

## Diagnosis

- Incident type: failed apply / stuck lock / state issue / drift / break-glass
- Root cause:
- Affected resources:
- User impact:

## Decision

- Recovery path: rollback / fix-forward / state restore / force-unlock / import / break-glass
- Why this path:
- Alternatives rejected:
- Approval:

## Execution

Commands/actions:

\`\`\`text

\`\`\`

## Verification

- Post-incident plan exit code:
- Drift status:
- Runtime checks:
- Rollback needed:

## Follow-up

- Preventive action:
- Policy/test/runbook update:
TEMPLATE
