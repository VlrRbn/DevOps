# Lesson 77: CloudTrail Audit Evidence & Portfolio Packaging

This lesson closes the Terraform delivery capstone by collecting AWS-side audit evidence and preparing a redacted portfolio package.

## Files

- `lesson.en.md` / `lesson.ru.md` - full lesson text.
- `proof-pack.en.md` / `proof-pack.ru.md` - evidence checklist.
- `scripts/cloudtrail-audit-snapshot.sh` - read-only CloudTrail evidence collector.
- `lab_77/audit-trail/` - optional Terraform root for a dedicated CloudTrail trail and focused S3 data events.
- `lab_77/README.md` - explains lab modes and audit-trail usage.
- `evidence/` - ignored local folder for raw audit evidence.

## Quick Start

```bash
chmod +x lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/scripts/*.sh
bash -n lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/scripts/cloudtrail-audit-snapshot.sh
```

Collect CloudTrail evidence after running lesson 76 workflows:

```bash
lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/scripts/cloudtrail-audit-snapshot.sh \
  --region eu-west-1 \
  --state-bucket YOUR_STATE_BUCKET \
  --state-prefix lab76/ \
  --start-time 2026-07-01T10:00:00Z \
  --end-time 2026-07-01T11:00:00Z \
  --release-id l76-demo \
  --workflow-url https://github.com/OWNER/REPO/actions/runs/123456789 \
  --trail-name YOUR_TRAIL_NAME
```

## Requirements

CloudTrail snapshot:

- AWS CLI configured with read access to `sts:GetCallerIdentity` and `cloudtrail:LookupEvents`
- `jq` optional but useful for manual review
- recent CloudTrail management events in the target region

## Safety Notes

- The snapshot script is read-only.
- CloudTrail evidence can contain account IDs, ARNs, usernames, IPs, DNS names, and internal metadata.
- Do not commit raw evidence unless it is intentionally redacted.
- S3 object-level state audit requires CloudTrail data events configured before the object access happens.
- `aws cloudtrail lookup-events` is useful for recent management events; object-level S3 data events usually require CloudTrail Lake, Athena over trail logs, or another configured destination.
- Do not enable broad S3 data events without cost review.

## What This Lesson Intentionally Does Not Add

- No new application stack: the lesson audits the lesson 76 capstone instead of deploying another copy.
- Optional audit Terraform exists: `lab_77/audit-trail/` creates a dedicated CloudTrail trail when you want production-style evidence.
- No policy-as-code engine: policy decisions were covered in earlier lessons.
- No lesson-specific CI workflow: CloudTrail evidence depends on account history, region, timing, and data-event configuration.
- Proof-pack stays: evidence collection and redaction are the core practice of this lesson.

## Optional Audit Trail

Use this when you want a real trail, long-term log delivery, and focused S3 data events for Terraform state:

```bash
cd lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/lab_77/audit-trail
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Keep `terraform_state_prefixes` narrow. Do not turn on broad S3 data events for every bucket.

## Suggested Flow

```text
Run lesson 76 workflow
-> collect CloudTrail audit snapshot
-> write state backend audit decision
-> correlate GitHub run with AWS role assumption
-> redact evidence
```

## Troubleshooting

| Symptom | Likely cause | Check |
| --- | --- | --- |
| `missing required command: aws` | AWS CLI is not installed or not on `PATH` | run `aws --version` |
| No OIDC event found | wrong region, wrong time window, or workflow did not assume AWS role | check GitHub job logs and CloudTrail region |
| No S3 object access events | S3 data events were not enabled before the access | document the limitation or query CloudTrail Lake/Athena if configured |
