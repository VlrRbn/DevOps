# Runbook: Restore Terraform State From S3 Version

## Use Only When

- Current remote state is corrupted or overwritten.
- Previous S3 object version is known-good.
- Current state has been snapshotted.
- All applies are frozen.
- Reviewer approves restore.

## Do Not Use For

- Normal application rollback.
- Fixing bad Terraform configuration.
- Avoiding `import`, `moved`, or `state mv` work.
- Guessing.

## Procedure

1. Freeze all Terraform workflows.
2. Snapshot current state with `terraform state pull`.
3. List S3 object versions.
4. Identify candidate previous version.
5. Download candidate state to local file.
6. Compare current vs candidate.
7. Approve restore.
8. Restore previous version to current key.
9. Run `terraform plan -detailed-exitcode`.
10. Document decision and verification.

## Download Candidate Version

```bash
aws s3api get-object \
  --bucket "$TF_STATE_BUCKET" \
  --key "lab74/dev/full/terraform.tfstate" \
  --version-id "$VERSION_ID" \
  previous-state.json
```

## Restore Candidate Version

This command changes the current remote state object. Do not run it during the normal lesson walkthrough. Use it only in an isolated recovery lab or during an approved incident.

```bash
aws s3api copy-object \
  --bucket "$TF_STATE_BUCKET" \
  --copy-source "${TF_STATE_BUCKET}/lab74/dev/full/terraform.tfstate?versionId=${VERSION_ID}" \
  --key "lab74/dev/full/terraform.tfstate"
```

After restore, do not apply immediately. First run `terraform plan -detailed-exitcode` and classify any diff.

## Evidence

- current state snapshot
- candidate version ID
- comparison notes
- approval
- post-restore plan
