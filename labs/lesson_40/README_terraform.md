# How to read my Terraform layout (lesson_40)

Root:
- main.tf: defines provider and calls module "network"
- variables.tf: defines root-level inputs
- outputs.tf: exposes IDs from modules
- envs/dev.tfvars: concrete values for Dev environment

Module "network":
- modules/network/main.tf: VPC, subnets, IGW, route tables, security groups
- modules/network/variables.tf: configurable inputs (CIDRs, tags, region)
- modules/network/outputs.tf: VPC ID, subnet IDs, SG IDs for root usage

Commands:
- terraform init
- terraform fmt
- terraform validate
- terraform plan -var-file=envs/dev.tfvars

OR:

- tflocal init
- tflocal plan -var-file=envs/dev.tfvars