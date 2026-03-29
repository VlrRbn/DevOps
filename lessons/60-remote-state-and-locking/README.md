# Lesson 60: Remote State & Locking

## Purpose

This lesson moves Terraform state from local disk to an S3 backend with:

- remote state storage
- backend locking
- S3 versioning
- safer recovery workflow

This is the baseline for any real shared Terraform usage.

## Prerequisites

- AWS CLI configured
- Terraform already working in at least one env
- understanding that state may contain sensitive data

## Layout

- `lesson.en.md`
  - full lesson theory, migration flow, drills, acceptance (EN)
- `lesson.ru.md`
  - full lesson theory, migration flow, drills, acceptance (RU)
- `proof-pack.en.md`
  - what evidence to save and how to collect it (EN)
- `proof-pack.ru.md`
  - what evidence to save and how to collect it (RU)
- `lab_60/terraform/backend-bootstrap/main.tf`
  - local-state bootstrap config for S3 backend bucket
- `lab_60/terraform/envs/backend.hcl`
  - backend config for migrated envs

## Quick Start

```bash
# 1) Bootstrap backend bucket
cd lessons/60-remote-state-and-locking/lab_60/terraform/backend-bootstrap
terraform init
terraform apply -var="state_bucket_name=vlrrbn-tfstate-123456789012-eu-west-1"

# 2) In your real envs root, add:
# terraform { backend "s3" {} }

# 3) Migrate local state to S3
cd lessons/60-remote-state-and-locking/lab_60/terraform/envs
terraform init -backend-config=backend.hcl -migrate-state
```

## Verification

```bash
terraform state pull | head -n 20
aws s3 ls s3://vlrrbn-tfstate-123456789012-eu-west-1/lab60/dev/full/terraform.tfstate
```

Locking drill:

```bash
# terminal A
terraform apply

# terminal B
terraform plan -lock-timeout=30s
```

This drill needs a non-empty plan. If terminal A says `No changes`, introduce one harmless temporary diff first.

## Recovery

List state versions:

```bash
aws s3api list-object-versions \
  --bucket vlrrbn-tfstate-123456789012-eu-west-1 \
  --prefix lab60/dev/full/terraform.tfstate
```

Download old version:

```bash
aws s3api get-object \
  --bucket vlrrbn-tfstate-123456789012-eu-west-1 \
  --key lab60/dev/full/terraform.tfstate \
  --version-id <VERSION_ID> \
  /tmp/terraform.tfstate.old
```

## Notes

- Native S3 lockfile is the recommended model for this track.
- `force-unlock` is incident-level tooling, not a convenience shortcut.
- Never reuse one backend `key` for multiple environments.
- If AWS CLI bucket checks appear to hang, retry with `--region`, `--no-cli-pager`, and explicit CLI timeouts.
- After successful migration, `envs/terraform.tfstate*` are no longer the source of truth; remote backend state is.