# Lab 55: Rolling Deployments with ASG Instance Refresh (Single Fleet)

## Purpose
This lab demonstrates safe application deployment with:
- one internal ALB
- one target group
- one Auto Scaling Group (single fleet)
- ASG Instance Refresh as the rollout engine
- immutable AMI-based versioning (`BUILD_ID` on page output)

The lab is intentionally different from Blue/Green (Lab 54):
- no weighted traffic split
- no dual web fleets
- rollout is done inside one ASG by replacing instances gradually

## Architecture

Traffic and control flow:
- Client -> SSM Session Manager -> `ssm_proxy` (private EC2)
- `ssm_proxy` -> internal ALB (`:80`)
- ALB -> single target group -> single ASG (`web`)
- ASG uses Launch Template with `web_ami_id`
- changing `web_ami_id` triggers Instance Refresh

Networking/security model:
- private web and proxy instances
- internal ALB only
- no NAT for private subnets
- SSM connectivity via VPC interface endpoints (`ssm`, `ssmmessages`, `ec2messages`)
- IMDSv2 required on web and proxy instances

## Prerequisites

- AWS account and IAM permissions for VPC/EC2/ALB/ASG/IAM/CloudWatch/SSM
- AWS CLI configured (`aws configure`)
- Session Manager Plugin installed
- Terraform `~> 1.14.0`
- Packer installed

## Layout
```text
lesson_55/
  lesson_55.md
  README.md
  SSM_PROXY_STABILITY_REPORT_ENG.md
  SSM_PROXY_STABILITY_REPORT_RU.md
lab_55/
  packer/
    README.md
    web/
    ssm_proxy/
  terraform/
    envs/
    modules/network/
```

Quick local checks:

```bash
aws --version
session-manager-plugin --version
terraform version
packer version
```

## 1) Build AMIs (Packer)
### 1.1 Build web AMIs
Web AMI includes nginx + page template + boot-time render service.
Rendered page shows:
- `BUILD_ID`
- hostname
- instance-id

```bash
cd lesson51_60/lesson_55/lab_55/packer/web

packer init .
packer validate .

packer build -var 'build_id=55-01' .
packer build -var 'build_id=55-02' .
```

### 1.2 Build SSM proxy AMI
Proxy AMI installs and stabilizes SSM agent (deb-based flow).

```bash
cd ../ssm_proxy

packer init .
packer validate .
packer build .
```

### 1.3 Capture AMI IDs
Use AWS Console or CLI and record:
- `WEB_AMI_55_01`
- `WEB_AMI_55_02`
- `SSM_PROXY_AMI`

## 2) Configure Terraform Inputs
Edit:
- `lesson51_60/lesson_55/lab_55/terraform/envs/terraform.tfvars`

Required AMI variables:
- `web_ami_id = "<WEB_AMI_55_01>"`
- `ssm_proxy_ami_id = "<SSM_PROXY_AMI>"`

Core rollout controls:
- `web_min_size`
- `web_desired_capacity`
- `web_max_size`
- `asg_min_healthy_percentage`
- `asg_instance_warmup_seconds`

Recommended for deterministic rollout tests:
- `web_min_size = 2`
- `web_desired_capacity = 2`
- `web_max_size = 2`
- `asg_min_healthy_percentage = 50`

## 3) Deploy Infrastructure
```bash
cd lesson51_60/lesson_55/lab_55/terraform/envs

terraform init
terraform plan
terraform apply
```

Useful outputs:

```bash
terraform output -raw web_asg_name
terraform output -raw web_tg_arn
terraform output -raw alb_dns_name
terraform output -raw ssm_proxy_instance_id
```

## 4) Validate Baseline (55-01)
### 4.1 Check SSM proxy status
```bash
IID="$(terraform output -raw ssm_proxy_instance_id)"
aws --region eu-west-1 ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$IID" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text
```

Expected: `Online`

### 4.2 Sample app response through proxy
Local terminal:

```bash
ALB_DNS="$(terraform output -raw alb_dns_name)"
echo "$ALB_DNS"
aws --region eu-west-1 ssm start-session --target "$IID"
```

Inside SSM session:

```bash
# paste ALB_DNS value from local terminal
for i in {1..30}; do
  curl -s -H 'Connection: close' "http://$ALB_DNS/" | grep -E 'BUILD|Hostname|InstanceId' || true
done
```

Expected: only `BUILD_ID: 55-01`

## 5) Rolling Update (55-01 -> 55-02)
1. Update `web_ami_id` in `terraform.tfvars` to `<WEB_AMI_55_02>`.
2. Apply:

```bash
terraform plan
terraform apply
```

This updates Launch Template image and automatically starts ASG Instance Refresh.

### Observe refresh
```bash
ASG_NAME="$(terraform output -raw web_asg_name)"
TG_ARN="$(terraform output -raw web_tg_arn)"

aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-records 5 \
  --output table

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LaunchTemplate.Version,LifecycleState,HealthStatus]' \
  --output table

aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --output table
```

Expected transition in sampler:
- mostly `55-01`
- mixed
- mostly/all `55-02`

## 6) Rollback
Rollback is artifact-based:
1. Set `web_ami_id` back to last known good AMI.
2. `terraform apply`
3. Verify new refresh and healthy end state.

## 7) Troubleshooting
### `TargetNotConnected` / `ConnectionLost` for proxy

Check:
- proxy IAM instance profile attached (`AmazonSSMManagedInstanceCore`)
- SSM interface endpoints exist and are `available`
- proxy SG can reach:
  - ALB on `80/tcp`
  - VPC resolver `53/tcp,53/udp`
  - endpoint SG on `443/tcp`
- `amazon-ssm-agent` active on proxy AMI

### Security Group dependency errors on apply/destroy
If you see `DependencyViolation`, find who references SG:

```bash
aws --region eu-west-1 ec2 describe-security-groups \
  --filters "Name=ip-permission.group-id,Values=<SG_ID>" \
  --query 'SecurityGroups[].{OwnerSG:GroupId,Name:GroupName,VpcId:VpcId}' \
  --output table
```

Then reconcile stale SG rules (import or revoke) and re-apply.

### Refresh does not complete
Common causes:
- new AMI not healthy in target group
- warmup too low
- broken nginx or app health behavior

Use:
- target health
- instance refresh status
- ALB/TG CloudWatch alarms

## 8) Destroy
```bash
cd lesson51_60/lesson_55/lab_55/terraform/envs
terraform destroy
```

## Notes
- For lesson narrative and drills, see:
  - `lesson51_60/lesson_55/lesson_55.md`
- For SSM proxy incident analysis and fixes, see:
  - `lesson51_60/lesson_55/lab_55/SSM_PROXY_STABILITY_REPORT_ENG.md`
  - `lesson51_60/lesson_55/lab_55/SSM_PROXY_STABILITY_REPORT_RU.md`
