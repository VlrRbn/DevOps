# Runbook: Emergency State Pull/Push

## Warning

`terraform state push` is a last-resort operation. Prefer S3 object version restore, `import`, `moved`, or `state mv` when they solve the problem.

## Use Only If

- Remote state must be manually corrected.
- S3 version restore is not enough.
- Candidate state file has been reviewed.
- All workflows are frozen.
- Approval exists.

## Procedure

1. Freeze Terraform workflows.
2. Snapshot current state:
   ```bash
   terraform state pull > before.json
   ```
3. Prepare `candidate.json`.
4. Validate JSON format.
5. Compare `before.json` and `candidate.json`.
6. Peer review.
7. Push only if approved. This command overwrites remote Terraform state:
   ```bash
   terraform state push candidate.json
   ```
8. Run `terraform plan -detailed-exitcode`.
9. Document everything.

Do not use `terraform state push` for ordinary rollback, configuration errors, or convenience cleanup.

## Evidence

- `before.json` location
- candidate state location
- diff/comparison summary
- approval
- post-push plan
