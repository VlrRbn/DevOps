# lab42 Terraform Safe Ops: cheap vs full envs, apply/destroy

“This folder = one environment = one state. Never run full from env-cheap.”

⚠️ This runbook assumes:
- single environment per state
- never switching cheap ↔ full on the same state

## Before apply (every time)
- [ ] I am in the correct folder: labs/lesson_42/terraform
- [ ] I am using the intended tfvars file (cheap vs full)
- [ ] allowed_ssh_cidr is my real public IP/32
- [ ] I understand what will be created (terraform plan reviewed)

## Commands (cheap)
terraform fmt -recursive
terraform init
terraform validate
terraform plan -var-file=envs/cheap.tfvars
terraform apply -var-file=envs/cheap.tfvars

## Commands (full)
terraform plan -var-file=envs/full.tfvars
terraform apply -var-file=envs/full.tfvars

## After testing (same day)
terraform destroy -var-file=envs/full.tfvars
# or cheap.tfvars

## If something looks wrong
terraform state list
terraform show
terraform state show <resource_address>

## Emergency stop
If plan shows unexpected destroy:
- STOP
- do NOT apply
- inspect state and addresses

## Strict rule
No manual changes in AWS console unless explicitly documented.
