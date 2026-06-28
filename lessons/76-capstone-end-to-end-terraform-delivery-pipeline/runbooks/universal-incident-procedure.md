# Runbook: Universal Terraform Incident Procedure

## Purpose

Use this runbook before choosing a specific recovery path such as failed apply recovery, stuck lock handling, state restore, state push, drift reconciliation, rollback, fix-forward, or break-glass.

The goal is to prevent panic actions from making Terraform state, AWS reality, or production impact worse.

## Core Rule

```text
Stop, snapshot, diagnose, decide, execute, verify, document.
```

Do not start with `apply`, `force-unlock`, `state push`, `state rm`, S3 state restore, or manual AWS changes.

## Universal Flow

1. Freeze automatic applies for the affected environment.
2. Identify the affected environment and state key.
3. Capture commit SHA, workflow run URL, operator, and time.
4. Create a state snapshot before recovery work.
5. Capture a fresh `terraform plan -detailed-exitcode`.
6. Check AWS reality for affected resources.
7. Classify the incident type and severity.
8. Choose one recovery path.
9. Execute one controlled action.
10. Run post-incident verification.
11. Save the incident decision record.
12. Create follow-up work to prevent recurrence.

## Severity Examples

| Severity | Example | Recovery posture |
| --- | --- | --- |
| SEV-3 | failed local plan | normal fix path |
| SEV-2 | failed apply in dev/stage | snapshot, diagnose, fix-forward or no-op |
| SEV-1 | production traffic degraded | freeze applies, restore service first |
| SEV-0 | corrupted/wrong state, unsafe lock, bad state restore | stop all applies, require reviewer approval |

SEV-0 is about Terraform control-plane danger. It means Terraform may misunderstand resource ownership.

## Safety Stop List

Do not run these without separate approval and evidence:

- rerun `terraform apply` without reviewing the new plan;
- `terraform destroy`;
- `terraform force-unlock` without proving the lock is stale;
- `terraform state push`;
- `terraform state rm`;
- S3 state object overwrite/delete/restore;
- `-target` as a permanent recovery method;
- production state repair from a local machine without peer review.

If a command changes remote state or real infrastructure, it requires evidence, approval, and a post-check.

## Decision Matrix

| Symptom | Likely issue | First safe step | Usually correct path | Avoid first |
| --- | --- | --- | --- | --- |
| Apply failed halfway | partial apply | snapshot + new plan | fix-forward or no-op | rerun apply blindly |
| Lock does not clear | active or stale lock | check active CI/local runs | wait or force-unlock with approval | force-unlock without proof |
| Plan shows unexpected replace | drift/config/state mismatch | compare AWS reality and state | investigate, import, moved block, or config fix | apply immediately |
| State object is corrupted | state corruption | freeze + snapshot + list versions | S3 version restore | state push first |
| Manual console change | drift after emergency | plan + AWS check | revert manual change or codify it | ignore drift |
| Production traffic is broken | service incident | freeze applies + restore service | fix-forward or rollback by impact | state surgery without cause |

## Evidence Checklist

Save or reference:

- incident ID;
- affected environment;
- state key;
- Git commit SHA;
- workflow run URL, if CI was involved;
- operator and reviewer;
- state snapshot path;
- plan output and exit code;
- AWS reality check notes;
- selected recovery path;
- rejected alternatives;
- approval;
- post-incident plan output;
- service health verification;
- follow-up action.

## Example: Failed Apply

```text
Symptom: apply failed while updating an Auto Scaling Group.
First action: freeze applies and run state-snapshot.sh dev.
Diagnosis: new plan shows the same ASG tag update only.
Decision: fix-forward by allowing the missing IAM action, then rerun controlled apply.
Rejected: state restore, because state is not corrupted.
Verification: post-incident plan is clean or remaining diff is understood.
```

## Example: Stale Lock

```text
Symptom: Terraform reports a lock, but the previous CI job was cancelled.
First action: check GitHub Actions and local terminals for active runs.
Decision: force-unlock only if no active run exists and approval is recorded.
Rejected: immediate force-unlock, because another process may still own the lock.
Verification: plan runs after unlock and no unexpected diff appears.
```

## Example: State Corruption

```text
Symptom: state object was overwritten or restored incorrectly.
First action: freeze all applies and snapshot current state.
Diagnosis: list S3 object versions and compare candidate state files.
Decision: S3 version restore only after reviewer approval.
Rejected: terraform state push first, because it is a last-resort operation.
Verification: terraform plan is understood after restore.
```

## Exit Criteria

An incident is not closed until:

- backend is reachable;
- `terraform state pull` works;
- post-incident plan is understood;
- unexpected diffs are resolved or accepted;
- service health is verified outside Terraform;
- emergency/manual changes are reconciled;
- decision record is saved;
- follow-up action exists.
