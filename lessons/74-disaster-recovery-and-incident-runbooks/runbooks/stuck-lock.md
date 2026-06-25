# Runbook: Stuck Terraform Lock

## Symptoms

- Terraform reports that state is locked.
- Previous CI/local Terraform run crashed or was cancelled.
- Lock object remains, but no Terraform process should own it.

## Immediate Actions

1. Check GitHub Actions for active runs.
2. Check local terminals and teammates.
3. Confirm no apply/plan is currently using the lock.
4. Record lock ID and lock metadata.
5. Use `terraform force-unlock` only when the lock is truly stale.

## Command

This is a real recovery command, not a drill command. Do not run it until the checks above are complete and approval is recorded.

```bash
terraform force-unlock <LOCK_ID>
```

## Safety Rules

- Never force-unlock while another Terraform command may be running.
- Never force-unlock because you are impatient.
- Record who approved the unlock.
- Run a plan after unlock.

## Evidence

- lock error text
- active run check
- approval note
- post-unlock plan output
