# Lesson 51: ASG Scaling Policies & Instance Refresh

## Purpose
Turn a static Auto Scaling Group into a reactive, self-healing system using
target tracking, scaling policies, CloudWatch metrics, and instance refresh.

## Prerequisites
- AWS account and credentials configured (`aws configure` or env vars).
- `packer`, `terraform`, `aws` CLI installed.
- Permissions to create: VPC, subnets, ALB, ASG, IAM, SSM, CloudWatch.

## Layout
- `lesson51_60/lesson_51/lesson_51.md`: lesson notes, drills, and checklists.
- `lesson51_60/lesson_51/lab_51/packer`: Packer templates and scripts.
- `lesson51_60/lesson_51/lab_51/terraform`: Terraform env + network module.

## Packer: build AMIs
Key files:
- `lesson51_60/lesson_51/lab_51/packer/web.pkr.hcl` (web AMI build)
- `lesson51_60/lesson_51/lab_51/packer/ssm_proxy.pkr.hcl` (SSM proxy AMI build)
- `lesson51_60/lesson_51/lab_51/packer/locals.pkr.hcl` (AMI filters, owners, tags)
- `lesson51_60/lesson_51/lab_51/packer/variables.pkr.hcl` (region, SSH user, instance type)
- `lesson51_60/lesson_51/lab_51/packer/scripts/install-nginx.sh` (install nginx)
- `lesson51_60/lesson_51/lab_51/packer/scripts/web-content.sh` (seed index template)
- `lesson51_60/lesson_51/lab_51/packer/scripts/render-index.sh` (render runtime metadata)
- `lesson51_60/lesson_51/lab_51/packer/scripts/render-index.service` (oneshot unit)
- `lesson51_60/lesson_51/lab_51/packer/scripts/setup-render.sh` (install render + meta.env)
- `lesson51_60/lesson_51/lab_51/packer/scripts/install-ssm-agent.sh` (ensure SSM agent)
- `lesson51_60/lesson_51/lab_51/packer/scripts/disable-nginx.sh` (failure drill)

Build:
```bash
cd lesson51_60/lesson_51/lab_51/packer
packer init .
packer fmt .
packer validate .
packer build -only=amazon-ebs.web .
packer build -only=amazon-ebs.ssm_proxy .
```

Notes:
- `disable-nginx.sh` is optional; enable it only for the failure drill.
- `setup-render.sh` writes AMI metadata into `/etc/web-build/meta.env` and
  installs a oneshot systemd unit to render runtime metadata into the homepage.

## Terraform: deploy the ASG
Key files:
- `lesson51_60/lesson_51/lab_51/terraform/envs/main.tf`
- `lesson51_60/lesson_51/lab_51/terraform/envs/terraform.tfvars`
- `lesson51_60/lesson_51/lab_51/terraform/modules/network/main.tf`

Steps:
1) Put the AMI ID(s) from Packer into
   `lesson51_60/lesson_51/lab_51/terraform/envs/terraform.tfvars`.
2) Apply:
```bash
cd lesson51_60/lesson_51/lab_51/terraform/envs
terraform init
terraform apply
```

Important variables (see `terraform.tfvars`):
- `web_ami_id`, `ssm_proxy_ami_id` (from Packer build output)
- `enable_nat`, `enable_ssm_vpc_endpoints`, `enable_web_ssm`
- `public_subnet_cidrs`, `private_subnet_cidrs`

What the module creates:
- VPC, public/private subnets, optional NAT.
- Internal ALB and target group.
- Launch Template + Auto Scaling Group for web.
- Target tracking scaling policy + instance refresh configuration.
- SSM proxy instance + optional SSM VPC endpoints.

## Validate
The ALB is internal, so validate via SSM port forwarding:
```bash
cd lesson51_60/lesson_51/lab_51/terraform/envs
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
- `lesson51_60/lesson_51/lesson_51.md`

Quick load test (via SSM port forwarding):
```bash
ab -t 300 -c 200 http://127.0.0.1:8080/
```

## Common Issues
- Internal ALB DNS does not resolve outside VPC: use SSM port forwarding.
- Load test too weak: increase duration (`-t`) or concurrency (`-c`).
- SSM not working: if `enable_ssm_vpc_endpoints=false`, NAT must be enabled.
- CloudWatch metrics can lag 1–3 minutes.

## Outputs (useful)
- `alb_dns_name`
- `ssm_proxy_instance_id`
- `web_instance_ids`
- `web_private_ips`

## Cleanup
```bash
cd lesson51_60/lesson_51/lab_51/terraform/envs
terraform destroy
```

## Notes
- Target tracking is the default scaling mode. Step scaling is kept as a reference.
- Instance refresh is tied to launch template changes.

## Cleanup
```bash
cd lesson51_60/lesson_51/lab_51/terraform/envs
terraform destroy
```
