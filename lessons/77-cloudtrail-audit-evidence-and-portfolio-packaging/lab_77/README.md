# Lab 77: CloudTrail Audit Layer

This lab does not deploy another application stack. It audits the delivery pipeline from lesson 76.

## Modes

### 1. Event History only

Use this mode when you only need recent management events:

```bash
lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/scripts/cloudtrail-audit-snapshot.sh \
  --region eu-west-1 \
  --state-bucket YOUR_TFSTATE_BUCKET \
  --state-prefix lab76/dev/full/ \
  --release-id YOUR_RELEASE_ID \
  --workflow-url https://github.com/OWNER/REPO/actions/runs/RUN_ID
```

This can show role assumptions and recent API calls, but it does not prove S3 object-level state access unless data events were already enabled.

### 2. Optional audit trail

Use `audit-trail/` when you want a real CloudTrail trail, log delivery to S3, and focused S3 data events for Terraform state:

```bash
cd lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/lab_77/audit-trail
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

The default `terraform_state_prefixes` map covers:

```text
dev   -> lab76/dev/full/
stage -> lab76/stage/full/
prod  -> lab76/prod/full/
```

Keep these prefixes narrow. Do not enable broad S3 data events for every bucket in the account.

## Evidence

Save these if you apply the optional audit trail:

```text
audit-trail-plan.txt
audit-trail-apply.txt
audit-trail-outputs.txt
cloudtrail-event-selectors.json
```

Then run the snapshot script with `--trail-name` so it collects selector evidence:

```bash
../../scripts/cloudtrail-audit-snapshot.sh \
  --region eu-west-1 \
  --state-bucket YOUR_TFSTATE_BUCKET \
  --state-prefix lab76/dev/full/ \
  --trail-name "$(terraform output -raw trail_name)"
```

## Cleanup

By default, `force_destroy_log_bucket = false`. This is intentional: audit logs should not disappear accidentally.

If `terraform destroy` leaves the log bucket behind with `BucketNotEmpty`, either keep it as evidence or intentionally empty object versions/delete markers before rerunning destroy.

Do not delete audit logs if they are still needed for a proof-pack or investigation.
