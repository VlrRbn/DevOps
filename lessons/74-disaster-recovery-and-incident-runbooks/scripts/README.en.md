# Lesson 74 Scripts

This folder contains helper scripts for Terraform incident recovery. Their job is to collect evidence, capture current state, and prepare an incident decision record.

The scripts do not perform recovery automatically. This is intentional: state restore, `force-unlock`, `state push`, rollback, and manual changes must go through an explicit decision and review.

## Safety Model

- The scripts do not run `terraform apply`, `terraform destroy`, `terraform force-unlock`, `terraform state push`, or S3 restore.
- The scripts may read Terraform state, the remote backend, Git metadata, and AWS S3 object versions.
- Generated evidence can contain sensitive data: state, account IDs, internal DNS names, IP addresses, ARNs, and provider output values.
- Do not commit raw evidence to public Git. Redact sensitive fields or publish only a short summary.
- Use `OUT_DIR` if you want evidence written outside the lesson folder.

## Requirements

- Terraform is installed and available in `PATH`.
- AWS CLI is required for `list-state-versions.sh` and `runtime-health-check.sh`.
- `jq` is required for `runtime-health-check.sh`.
- Terraform backend is configured for the selected environment.
- AWS credentials can read backend/state data.
- S3 version checks need permission to list object versions.
- Runtime health checks need read-only access to STS, ELBv2, Auto Scaling, and CloudWatch.
- Commands can run from the repository root or from any directory if you use the full script path.

## Scripts

| Script | Purpose | Changes infrastructure/state? |
|---|---|---|
| `state-snapshot.sh` | Captures current Terraform state and current plan before recovery. | No |
| `post-incident-check.sh` | Captures a post-incident `terraform plan` and recovery status. | No |
| `runtime-health-check.sh` | Collects runtime health evidence for the ALB Target Group, ASG, and CloudWatch alarms. | No |
| `list-state-versions.sh` | Lists S3 object versions for a Terraform state key. | No |
| `incident-decision-template.sh` | Generates a Markdown incident decision template. | No |

## `state-snapshot.sh`

Use this before any recovery action.

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/state-snapshot.sh dev
```

Custom evidence directory:

```bash
OUT_DIR=/tmp/l74-state-snapshot-dev \
lessons/74-disaster-recovery-and-incident-runbooks/scripts/state-snapshot.sh dev
```

Generated files:

```text
terraform-version.txt
git-sha.txt
git-status.txt
terraform-state-pull.json
terraform-state-pull-stderr.txt
terraform-state-pull-exitcode.txt
current-plan.txt
current-plan-exitcode.txt
snapshot-summary.txt
```

Important: `terraform-state-pull.json` is almost always sensitive. Do not publish it without redaction.

## `post-incident-check.sh`

Use this after recovery, rollback, fix-forward, or manual reconciliation.

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/post-incident-check.sh dev
```

The script prints one of these statuses:

- `CLEAN` - `terraform plan` returned exit code `0`; no changes.
- `DRIFT_OR_DIFF` - `terraform plan` returned exit code `2`; changes or drift exist.
- `ERROR` - `terraform plan` failed.

The script exits with `0` for `CLEAN`, `2` for `DRIFT_OR_DIFF`, and `1` for `ERROR`.

Generated files:

```text
terraform-version.txt
git-sha.txt
git-status.txt
post-incident-plan.txt
post-incident-plan-exitcode.txt
post-incident-summary.txt
```

`DRIFT_OR_DIFF` is not automatically bad. It means the plan must be read and reviewed.

## `runtime-health-check.sh`

Use this after the Terraform-level check to collect runtime evidence.

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/runtime-health-check.sh dev
```

The script checks:

- ALB Target Group health;
- ASG instance lifecycle/health;
- CloudWatch alarm states for release/safety alarms.

It does not `curl` the internal ALB. The ALB in this lab is private, so it is usually reachable from your local machine only through SSM port forwarding or VPN. The script uses AWS APIs instead.

Statuses:

- `RUNTIME_HEALTH_STATUS=HEALTHY` - targets are healthy and critical alarms are not in `ALARM`.
- `RUNTIME_HEALTH_STATUS=WARN` - warnings exist, for example `INSUFFICIENT_DATA`.
- `RUNTIME_HEALTH_STATUS=UNHEALTHY` - there are no healthy targets or a critical alarm is firing.
- `RUNTIME_HEALTH_STATUS=ERROR` - evidence collection failed.

Generated files:

```text
terraform-version.txt
git-sha.txt
git-status.txt
runtime-inputs.txt
aws-caller-identity.json
target-health.json
target-health-states.txt
asg.json
asg-instances.txt
cloudwatch-alarms.json
cloudwatch-alarm-states.txt
runtime-health-summary.txt
```

Exit codes:

- `0` - runtime looks healthy or only warnings were found;
- `1` - evidence collection failed;
- `2` - runtime is unhealthy.

## `list-state-versions.sh`

Use this when you need to identify available state versions in the S3 backend.

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/list-state-versions.sh \
  "$TF_STATE_BUCKET" \
  "lab74/dev/full/terraform.tfstate"
```

The script only lists object versions. It does not restore, copy, or delete state.

Save output like this:

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/list-state-versions.sh \
  "$TF_STATE_BUCKET" \
  "lab74/dev/full/terraform.tfstate" \
  > state-versions-dev.txt
```

Before publishing, check whether bucket name and state key can be disclosed.

## `incident-decision-template.sh`

Generates an incident decision template.

```bash
lessons/74-disaster-recovery-and-incident-runbooks/scripts/incident-decision-template.sh INC-001 dev \
  > incident-decision.md
```

Fill the file manually: symptom, diagnosis, chosen recovery path, approval, executed commands, verification, and follow-up.

## Exit Codes

- `64` - invalid arguments or environment is not one of `dev|stage|prod`.
- `state-snapshot.sh` saves the exit codes from `terraform state pull` and `terraform plan` into separate files. It exits `1` if state pull fails or if `terraform plan` exits `1`.
- `post-incident-check.sh` saves the `terraform plan` exit code and maps it to `CLEAN`, `DRIFT_OR_DIFF`, or `ERROR`. It exits `0`, `2`, or `1` respectively.
- `runtime-health-check.sh` returns `0`, `1`, or `2` and saves the status in `runtime-health-summary.txt`.

## Troubleshooting

### `Terraform root not found`

Check that you are using the current lesson folder and that `lab_74/terraform/envs/<env>` exists.

### `terraform state pull` failed

Common causes:

- backend is not initialized;
- AWS credentials are missing;
- S3 backend access is denied;
- backend bucket/key is wrong;
- the environment has not been applied yet.

The script still writes evidence when this fails, so the failure itself is documented.

### `post-incident-check.sh` returned `DRIFT_OR_DIFF`

Terraform sees changes. Read `post-incident-plan.txt` and decide whether this is the expected rollback/fix-forward result or new drift.

### `runtime-health-check.sh` returned `UNHEALTHY`

Check `target-health.json`, `asg.json`, and `cloudwatch-alarm-states.txt`. Common causes: targets are still warming up, ASG has not moved instances to `InService`, the application returns 5xx, or the health check path is wrong.

### `list-state-versions.sh` returns no versions

Check bucket name, state key, region, AWS profile, and whether S3 bucket versioning is enabled.

## Proof-Pack Link

At minimum, save:

- state snapshot folder path;
- `snapshot-summary.txt`;
- `current-plan-exitcode.txt`;
- `post-incident-summary.txt`;
- `post-incident-plan-exitcode.txt`;
- `runtime-health-summary.txt`;
- completed `incident-decision.md`.

Keep raw state and full plans local or in private evidence storage, not in a public repository.
