# Lesson 56: Guardrailed Deployments (Auto Rollback, Checkpoints, Skip Matching)

## Purpose

This lab upgrades rolling deployments from "works in good weather" to "safe under pressure" by adding deployment guardrails:

- CloudWatch alarm gates
- automatic rollback
- checkpoint validation
- skip matching

## Prerequisites

- Lesson 55 completed (Instance Refresh rollout/abort/rollback basics)
- AWS CLI, Terraform, Packer configured
- Internal ALB reachable through SSM proxy workflow
- Response includes deployment identity (`BUILD_ID`, hostname, instance-id)

## Layout

- `lesson.en.md`
  - full lesson theory, runbook, drills, acceptance (EN)
- `lesson.ru.md`
  - full lesson theory, runbook, drills, acceptance (RU)
- `lab_56/packer/web`
  - web AMI bake pipeline
- `lab_56/packer/ssm_proxy`
  - SSM proxy AMI
- `lab_56/packer/README.md`
  - Packer-specific notes and build commands for `web/` and `ssm_proxy/`
- `lab_56/terraform/envs`
  - environment entrypoint (`terraform.tfvars`, outputs)
- `lab_56/terraform/modules/network`
  - ASG/ALB/monitoring implementation

## Quick Start

```bash
# 1) Build new web AMI
cd lessons/56-guardrailed-deployments/lab_56/packer/web
packer build -var 'build_id=56-02' .

# 2) Deploy with Terraform
cd ../../terraform/envs
# set web_ami_id in terraform.tfvars first
terraform plan
terraform apply

# 3) Collect runtime identifiers
export ASG_NAME="$(terraform output -raw web_asg_name)"
export TG_ARN="$(terraform output -raw web_tg_arn)"
export ALB_DNS="$(terraform output -raw alb_dns_name)"
export PROJECT="$(terraform output -raw web_asg_name | sed 's/-web-asg$//')"
```

## Guardrail Verification

### Refresh state

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 5 \
  --query 'InstanceRefreshes[*].[Status,PercentageComplete,StatusReason]' \
  --output table
```

### Alarm gates

```bash
aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT}-target-5xx-critical" "${PROJECT}-alb-unhealthy-hosts" \
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

## Proxy Traffic Sample

Open SSM proxy session:

```bash
aws ssm start-session --target "$(terraform output -raw ssm_proxy_instance_id)"
```

Inside SSM session:

```bash
ALB_DNS="internal-...elb.amazonaws.com"
for i in {1..40}; do
  curl -s -H 'Connection: close' "http://$ALB_DNS/" | egrep -i 'BUILD|Hostname|InstanceId' || true
  sleep 1
done
```

## Drills

1. Good rollout with checkpoint validation
2. Bad AMI rollout with automatic rollback
3. Checkpoint Go/No-Go decision
4. Skip matching sanity check

## Troubleshooting

- Refresh not starting: verify LT version changed; if refresh did not auto-start, run `start-instance-refresh` manually and check alarm states.
- Frequent unhealthy targets: check warmup/grace/health endpoint behavior.
- No rollback on bad rollout: verify `auto_rollback = true` and alarm names wired in `alarm_specification`.
- No proof in traffic checks: ensure `BUILD_ID` is rendered in response body.

## Cleanup

```bash
cd lessons/56-guardrailed-deployments/lab_56/terraform/envs
terraform destroy
```

## Notes

- `skip_matching` reduces pointless churn but is not drift management.
- Keep alarms actionable; avoid noisy rollback loops.
