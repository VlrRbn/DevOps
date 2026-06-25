# Runbook: Failed Terraform Apply

## Symptoms

- `terraform apply` exits non-zero.
- Some resources may already be changed.
- The next plan may show partial work, replacement, or drift.

## Immediate Actions

1. Do not rerun apply blindly.
2. Save apply logs.
3. Run `scripts/state-snapshot.sh <env>`.
4. Run `terraform plan -detailed-exitcode` from the affected root.
5. Check AWS reality for changed resources.
6. Decide fix-forward, rollback, state reconciliation, or no-op.

If the next plan is unclear, stop and escalate. A second apply can make a partial failure worse.

## Diagnosis Questions

- Did Terraform fail before any resource changed?
- Did it fail after create/update/delete started?
- Did state update successfully?
- Does the next plan want to complete the same change?
- Does the next plan include destructive surprises?
- Is user traffic affected?

## Recovery Options

| Option | Use when | Avoid when |
| --- | --- | --- |
| Rerun apply | failure was transient and next plan is expected | plan is unclear or destructive |
| Fix-forward | a small config correction is safer | state is corrupted |
| Rollback | previous config/module version is known-good | rollback causes wider replacement |
| State surgery | reality is correct but state mapping is wrong | you have no snapshot/approval |

## Verification

- `terraform plan -detailed-exitcode` returns `0`, or remaining diff is explicitly approved.
- Drift workflow/check is clean.
- Runtime health checks pass.
- Incident decision is saved.

## Evidence

- apply log
- snapshot folder
- current plan
- decision note
- verification output
