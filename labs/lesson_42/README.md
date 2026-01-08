# Terraform lab 42

## Environments
- `envs/cheap.tfvars`: 1 public + 1 private subnet, 1 NAT (single-AZ)
- `envs/full.tfvars`: 2 public + 2 private subnets, NAT per AZ (HA)

## Usage
```bash
terraform init
terraform plan -var-file=envs/cheap.tfvars
terraform apply -var-file=envs/cheap.tfvars
```

## Notes
- Update `allowed_ssh_cidr` to real public IP `/32` before apply.
- `public_key` must be a valid SSH public key.
