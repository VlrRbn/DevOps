# Lesson 57: Deployment Quality Gates (Safety vs Quality Decisions)

## Purpose

This lab extends lesson 56 with a second decision layer:

- safety alarms for automatic rollback
- quality alarms for release Go/No-Go
- proof artifacts for release decisions

The key idea: not every regression should trigger immediate rollback. Safety protects availability, quality protects user experience and release confidence.

## Prerequisites

- Lesson 56 completed (Instance Refresh + rollback alarms)
- AWS CLI, Terraform, Packer configured
- Internal ALB reachable through SSM proxy workflow
- Response includes deployment identity (`BUILD_ID`, hostname, instance-id)

## Layout

- `lesson.en.md`
  - full lesson theory, runbook, drills, acceptance (EN)
- `lesson.ru.md`
  - full lesson theory, runbook, drills, acceptance (RU)
- `proof-pack.en.md`
  - what evidence to save and how to structure proof artifacts (EN)
- `proof-pack.ru.md`
  - what evidence to save and how to structure proof artifacts (RU)
- `lab_57/packer/web`
  - web AMI bake pipeline
- `lab_57/packer/ssm_proxy`
  - SSM proxy AMI (optional `-wrk` variant for heavier load generation)
- `lab_57/packer/README.md`
  - Packer-specific notes and build commands
- `lab_57/terraform/envs`
  - environment entrypoint (`terraform.tfvars`, outputs)
- `lab_57/terraform/modules/network`
  - ASG/ALB/monitoring implementation (safety + quality alarms)

## Quick Start

```bash
# 1) Build a new web AMIs
cd lessons/57-deployment-quality-gates/lab_57/packer/web
packer build -var 'build_id=57-01' .
packer build -var 'build_id=57-02' .

# 2) (Optional) Build dedicated proxy AMI with wrk installed
cd ../ssm_proxy
packer build -var 'build_id=57-wrk' .

# 3) Deploy with Terraform
cd ../../terraform/envs
# set web_ami_id (and optionally ssm_proxy_ami_id) in terraform.tfvars first
terraform plan
terraform apply

# 4) Collect runtime identifiers
export ASG_NAME="$(terraform output -raw web_asg_name)"
export TG_ARN="$(terraform output -raw web_tg_arn)"
export ALB_DNS="$(terraform output -raw alb_dns_name)"
export PROJECT="$(terraform output -raw web_asg_name | sed 's/-web-asg$//')"
```

## Gate Verification

### Refresh state

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 5 \
  --query 'InstanceRefreshes[*].[Status,PercentageComplete,StatusReason]' \
  --output table
```

### Safety alarms (auto rollback scope)

```bash
aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT}-target-5xx-critical" "${PROJECT}-alb-unhealthy-hosts" "${PROJECT}-alb-5xx-critical" \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table
```

### Quality alarms (manual release decision scope)

```bash
aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT}-release-target-5xx" "${PROJECT}-release-latency" \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table
```

### Target health

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table
```

## Load and Build Sampling

Use SSM tunnel, then generate traffic from your workstation or the proxy instance.

- baseline load: healthy endpoint (`/`)
- canary load: stress/error endpoint used in your drill (for example `/fail`)
- sample response identity repeatedly to prove mixed/new/old fleet behavior

For a documented artifact flow, follow `proof-pack.en.md` or `proof-pack.ru.md`.

## Drills

1. Baseline capture and quality gate baseline
2. Candidate rollout with quality observation window
3. Safety rollback scenario
4. Final Go/No-Go decision with proof pack

## Troubleshooting

- Refresh not starting: verify alarm states; instance refresh cannot start when monitored alarms are already in `ALARM`.
- Unexpected rollback: confirm which safety alarm fired and inspect target health/counters first.
- No quality signal: verify enough traffic volume and correct endpoint pattern.
- No identity proof: ensure response still renders `BUILD_ID`, hostname, and instance-id.

## Cleanup

```bash
cd lessons/57-deployment-quality-gates/lab_57/terraform/envs
terraform destroy
```

## Notes

- `alarm_specification` in ASG should contain safety alarms only.
- Quality alarms are decision aids for operators, not automatic rollback triggers.
- Keep proof artifacts for each release attempt to avoid guess-based decisions.
