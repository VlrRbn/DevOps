# Lesson 74: Disaster Recovery & Terraform Incident Runbooks

This lesson continues the Terraform delivery track from lessons 60-73 and focuses on operational recovery.

Main idea: policy gates and controlled apply reduce incidents, but they do not replace recovery runbooks.

## What Is Included

- `lesson.en.md` and `lesson.ru.md` - full lesson text
- `proof-pack.en.md` and `proof-pack.ru.md` - evidence checklist
- `runbooks/` - recovery procedures for common Terraform incidents
- `runbooks/*.RU.md` - Russian versions of the main runbooks
- `runbooks/universal-incident-procedure.md` - common incident flow and examples
- `runbooks/aws-reality-check-cheatsheet.RU.md` - Russian AWS CLI reality-check cheat sheet
- `scripts/README.en.md` and `scripts/README.ru.md` - script usage, safety model, evidence outputs, and troubleshooting
- `scripts/state-snapshot.sh` - state and plan snapshot before recovery
- `scripts/list-state-versions.sh` - safe S3 state version listing
- `scripts/post-incident-check.sh` - post-recovery plan capture
- `scripts/runtime-health-check.sh` - read-only runtime health evidence for ALB, ASG, and CloudWatch alarms
- `scripts/incident-decision-template.sh` - incident decision record template
- `lab_74/` - Terraform/Packer lab copied from the previous delivery chain
- `policies/` - inherited policy tests from previous lessons

## Quick Checks

From repo root:

```bash
terraform fmt -check -recursive lessons/74-disaster-recovery-and-incident-runbooks/lab_74/terraform
packer fmt -check -recursive lessons/74-disaster-recovery-and-incident-runbooks/lab_74/packer
bash -n lessons/74-disaster-recovery-and-incident-runbooks/scripts/*.sh
shellcheck lessons/74-disaster-recovery-and-incident-runbooks/scripts/*.sh lessons/74-disaster-recovery-and-incident-runbooks/policies/*.sh
lessons/74-disaster-recovery-and-incident-runbooks/policies/test-policy.sh
lessons/74-disaster-recovery-and-incident-runbooks/policies/test-cost-policy.sh
lessons/74-disaster-recovery-and-incident-runbooks/policies/test-opa.sh
```

Validate Packer templates from their own directories:

```bash
for dir in \
  lessons/74-disaster-recovery-and-incident-runbooks/lab_74/packer/web \
  lessons/74-disaster-recovery-and-incident-runbooks/lab_74/packer/ssm_proxy; do
  (cd "$dir" && packer init . && packer validate .)
done
```

Run module tests:

```bash
TF_DATA_DIR=/tmp/l74-module-test-data \
terraform -chdir=lessons/74-disaster-recovery-and-incident-runbooks/lab_74/terraform/modules/network \
  init -backend=false -input=false -no-color

TF_DATA_DIR=/tmp/l74-module-test-data \
terraform -chdir=lessons/74-disaster-recovery-and-incident-runbooks/lab_74/terraform/modules/network \
  test -no-color
```

Validate env roots without remote state:

```bash
for env in dev stage prod; do
  TF_DATA_DIR="/tmp/l74-${env}-data" \
  terraform -chdir="lessons/74-disaster-recovery-and-incident-runbooks/lab_74/terraform/envs/${env}" \
    init -backend=false -input=false -no-color

  TF_DATA_DIR="/tmp/l74-${env}-data" \
  terraform -chdir="lessons/74-disaster-recovery-and-incident-runbooks/lab_74/terraform/envs/${env}" \
    validate -no-color
done
```

## Safe Script Examples

Create a state snapshot before recovery:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/state-snapshot.sh dev
```

List S3 state versions:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/list-state-versions.sh \
  "$TF_STATE_BUCKET" \
  "lab74/dev/full/terraform.tfstate"
```

Create an incident decision file:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/incident-decision-template.sh INC-001 dev \
  > /tmp/incident-decision.md
```

Collect runtime health evidence after recovery:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/runtime-health-check.sh dev
```

## Safety Notes

- The scripts do not run `apply`, `force-unlock`, `state push`, or S3 restore.
- State snapshots may contain sensitive values. Keep raw evidence out of public Git.
- `force-unlock`, S3 restore, and `state push` are manual recovery actions that require approval and evidence.
- Rollback is not automatically safer than fix-forward.
- `lab_74/terraform/envs/*/.terraform/`, `backend.hcl`, `terraform.tfvars`, `tfplan`, and generated evidence are local runtime data and must stay ignored.
