# Runbook: Break-Glass Terraform / AWS Recovery

## Definition

Break-glass means using an emergency path outside normal automation.

## Valid Reasons

- Production is down.
- CI cannot assume role.
- Terraform backend is unavailable.
- Normal apply path is too slow for active incident impact.
- A security control must be changed immediately.

## Hard Rules

- Break-glass is not convenience.
- Access is time-limited.
- Every action is recorded.
- Manual changes must be reconciled into Terraform.
- Post-incident review is mandatory.
- Break-glass access must be revoked after the incident.

## Required Evidence

- what was done
- who did it
- when
- why normal path was not enough
- exact commands or console actions
- how Terraform control was restored
- follow-up action
