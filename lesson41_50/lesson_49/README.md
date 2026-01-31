# Lesson 49: Golden AMI with Packer + Terraform

## Purpose
Bake a reusable Ubuntu 24.04 + Nginx AMI with Packer, then deploy it with Terraform
behind an internal ALB. User data stays minimal; the AMI carries the software and
static content.

## Layout
- `lesson41_50/lesson_49/lesson_49.md`: narrative lesson notes and drills.
- `lesson41_50/lesson_49/lab_49/packer`: Packer template and provisioning scripts.
- `lesson41_50/lesson_49/lab_49/terraform`: Terraform env + network module.

## Packer: build the AMI
Key files:
- `lesson41_50/lesson_49/lab_49/packer/web.pkr.hcl` (web AMI build)
- `lesson41_50/lesson_49/lab_49/packer/scripts/install-nginx.sh` (install nginx)
- `lesson41_50/lesson_49/lab_49/packer/scripts/web-content.sh` (seed index template)
- `lesson41_50/lesson_49/lab_49/packer/scripts/render-index.sh` (render runtime metadata)
- `lesson41_50/lesson_49/lab_49/packer/scripts/render-index.service` (oneshot unit)
- `lesson41_50/lesson_49/lab_49/packer/scripts/setup-render.sh` (install render + meta.env)
- `lesson41_50/lesson_49/lab_49/packer/scripts/disable-nginx.sh` (optional failure simulation)

Build:
```bash
cd lesson41_50/lesson_49/lab_49/packer
packer init .
packer fmt .
packer validate .
packer build .
```

Notes:
- `scripts/disable-nginx.sh` is optional; enable/disable its provisioner in
  `web.pkr.hcl` when you want the failure simulation.
- `setup-render.sh` writes AMI metadata into `/etc/web-build/meta.env` and
  installs a oneshot systemd unit to render runtime metadata into the homepage.

## Terraform: deploy the AMI
Key files:
- `lesson41_50/lesson_49/lab_49/terraform/envs/main.tf`
- `lesson41_50/lesson_49/lab_49/terraform/envs/terraform.tfvars`
- `lesson41_50/lesson_49/lab_49/terraform/modules/network/main.tf`

Steps:
1) Put the AMI ID from Packer into
   `lesson41_50/lesson_49/lab_49/terraform/envs/terraform.tfvars`
   under `web_ami_id`.
2) Apply:
```bash
cd lesson41_50/lesson_49/lab_49/terraform/envs
terraform init
terraform apply
```

What the module creates:
- VPC, public/private subnets, optional NAT.
- Internal ALB and target group.
- Two private web EC2s from the baked AMI.
- SSM proxy instance + optional SSM VPC endpoints.

## Validate
The ALB is internal, so validate from the SSM proxy:
```bash
cd lesson41_50/lesson_49/lab_49/terraform/envs
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
cd lesson41_50/lesson_49/lab_49/terraform/envs
terraform destroy
```

## Extra notes
- `lesson41_50/lesson_49/lab_49/terraform/modules/network/scripts/web-userdata.sh`
  is an example of minimal user data and is not wired to instances by default.
