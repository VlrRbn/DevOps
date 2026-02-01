# Lesson 52: Observability & Cost Control (ASG + ALB)

## Purpose
Add AWS-native observability and cost-aware scaling to the ASG + ALB stack.
Focus on real user-impact signals, actionable alarms, and visibility into scaling decisions.

## Prerequisites
- AWS account and credentials configured (`aws configure` or env vars).
- `terraform`, `aws` CLI installed.
- AMI IDs available (from lesson_51 Packer builds).
- Permissions to create: VPC, subnets, ALB, ASG, IAM, SSM, CloudWatch.

## Layout
- `lesson51_60/lesson_52/lesson_52.md`: lesson notes, drills, and checklists.
- `lesson51_60/lesson_52/lab_52/packer`: AMI build assets (reuse from lesson_51 if needed).
- `lesson51_60/lesson_52/lab_52/terraform`: Terraform env + network module.

## Terraform: deploy the stack + alarms
Key files:
- `lesson51_60/lesson_52/lab_52/terraform/envs/main.tf`
- `lesson51_60/lesson_52/lab_52/terraform/envs/terraform.tfvars`
- `lesson51_60/lesson_52/lab_52/terraform/modules/network/main.tf`

Steps:
1) Put the AMI ID(s) into
   `lesson51_60/lesson_52/lab_52/terraform/envs/terraform.tfvars`.
2) Apply:
```bash
cd lesson51_60/lesson_52/lab_52/terraform/envs
terraform init
terraform apply
```

Important variables (see `terraform.tfvars`):
- `web_ami_id`, `ssm_proxy_ami_id`
- `enable_nat`, `enable_ssm_vpc_endpoints`, `enable_web_ssm`
- `public_subnet_cidrs`, `private_subnet_cidrs`

What the module creates:
- VPC, public/private subnets, optional NAT.
- Internal ALB and target group.
- Launch Template + Auto Scaling Group for web.
- Target tracking scaling policy + instance refresh configuration.
- ALB CloudWatch alarms (5XX + Unhealthy targets).
- SSM proxy instance + optional SSM VPC endpoints.

## Alarms (focus)
- `HTTPCode_ELB_5XX_Count` (Sum): critical user-impact signal.
- `UnHealthyHostCount` (Average > 0): capacity loss signal.
- `treat_missing_data = notBreaching` to avoid false alarms on empty periods.

## Validate
ALB is internal, so validate via SSM port forwarding:
```bash
cd lesson51_60/lesson_52/lab_52/terraform/envs
SSM_PROXY_ID="$(terraform output -raw ssm_proxy_instance_id)"
ALB_DNS="$(terraform output -raw alb_dns_name)"

aws ssm start-session \
  --target "$SSM_PROXY_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$ALB_DNS\"],\"portNumber\":[\"80\"],\"localPortNumber\":[\"8080\"]}"
```
Then from another terminal:
```bash
curl -s "http://127.0.0.1:8080/"
```

## Drills
Follow the drills in:
- `lesson51_60/lesson_52/lesson_52.md`

Quick load test (via SSM port forwarding):
```bash
ab -t 300 -c 200 http://127.0.0.1:8080/
```

## Common Issues
- Internal ALB DNS does not resolve outside VPC: use SSM port forwarding.
- CloudWatch metrics can lag 1-3 minutes.
- SSM not working: if `enable_ssm_vpc_endpoints=false`, NAT must be enabled.

## Outputs (useful)
- `alb_dns_name`
- `ssm_proxy_instance_id`
- `web_instance_ids`
- `web_private_ips`

## Cleanup
```bash
cd lesson51_60/lesson_52/lab_52/terraform/envs
terraform destroy
```

## Notes
- ALB metrics are the source of user-impact truth.
- Alerts should map to action, not noise.
- Target tracking stays the default scaling mode.
