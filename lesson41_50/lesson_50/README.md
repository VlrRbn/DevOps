# Lesson 50: Launch Template + Auto Scaling Group

## Purpose
Replace fixed EC2 instances with a self-healing web tier using a baked AMI,
Launch Template, Auto Scaling Group, and an internal ALB.

## Layout
- `lesson41_50/lesson_50/lesson_50.md`: narrative lesson notes and drills.
- `lesson41_50/lesson_50/lab_50/packer`: Packer templates and scripts.
- `lesson41_50/lesson_50/lab_50/terraform`: Terraform env + network module.

## Packer: build AMIs
Key files:
- `lesson41_50/lesson_50/lab_50/packer/web.pkr.hcl` (web AMI build)
- `lesson41_50/lesson_50/lab_50/packer/ssm_proxy.pkr.hcl` (SSM proxy AMI build)
- `lesson41_50/lesson_50/lab_50/packer/locals.pkr.hcl` (AMI filters, owners, tags)
- `lesson41_50/lesson_50/lab_50/packer/variables.pkr.hcl` (region, SSH user, instance type)
- `lesson41_50/lesson_50/lab_50/packer/scripts/install-nginx.sh` (install nginx)
- `lesson41_50/lesson_50/lab_50/packer/scripts/web-content.sh` (seed index template)
- `lesson41_50/lesson_50/lab_50/packer/scripts/render-index.sh` (render runtime metadata)
- `lesson41_50/lesson_50/lab_50/packer/scripts/render-index.service` (oneshot unit)
- `lesson41_50/lesson_50/lab_50/packer/scripts/setup-render.sh` (install render + meta.env)
- `lesson41_50/lesson_50/lab_50/packer/scripts/install-ssm-agent.sh` (ensure SSM agent)
- `lesson41_50/lesson_50/lab_50/packer/scripts/disable-nginx.sh` (failure drill)

Build:
```bash
cd lesson41_50/lesson_50/lab_50/packer
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
- `lesson41_50/lesson_50/lab_50/terraform/envs/main.tf`
- `lesson41_50/lesson_50/lab_50/terraform/envs/terraform.tfvars`
- `lesson41_50/lesson_50/lab_50/terraform/modules/network/main.tf`

Steps:
1) Put the AMI ID(s) from Packer into
   `lesson41_50/lesson_50/lab_50/terraform/envs/terraform.tfvars`.
2) Apply:
```bash
cd lesson41_50/lesson_50/lab_50/terraform/envs
terraform init
terraform apply
```

What the module creates:
- VPC, public/private subnets, optional NAT.
- Internal ALB and target group.
- Launch Template + Auto Scaling Group for web.
- SSM proxy instance + optional SSM VPC endpoints.

## Validate
The ALB is internal, so validate from the SSM proxy:
```bash
cd lesson41_50/lesson_50/lab_50/terraform/envs
SSM_PROXY_ID="$(terraform output -raw ssm_proxy_instance_id)"
ALB_DNS="$(terraform output -raw alb_dns_name)"
aws ssm start-session --target "$SSM_PROXY_ID"
```
Inside the session:
```bash
curl -s "http://$ALB_DNS"
```

## Cleanup
```bash
cd lesson41_50/lesson_50/lab_50/terraform/envs
terraform destroy
```
