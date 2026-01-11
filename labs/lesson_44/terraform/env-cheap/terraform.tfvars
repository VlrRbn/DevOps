aws_region   = "eu-west-1"
project_name = "lab44"
environment  = "cheap"

# Keep it simple: still use /16 for VPC, but only use 1 subnet per tier
vpc_cidr = "10.40.0.0/16"

# Only 1 public + 1 private subnet for cheap setup
public_subnet_cidrs  = ["10.40.1.0/24"]
private_subnet_cidrs = ["10.40.11.0/24"]

# IMPORTANT: set to real public IP /32 before apply
allowed_ssh_cidr = "0.0.0.0/32" # WARNING need PUBLIC_IP/32 --- curl -4 ifconfig.me

# No NAT at all is the cheapest
# enable_nat          = false
# enable_full_ha      = false
enable_nat = true

ssh_key_name          = "lab44_terraform"
instance_type_bastion = "t3.micro"
instance_type_web     = "t3.micro"
ssh_public_key        = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKWfwU+2WOaa5CeywI+J4TX8jzqam+QgiUPNerdBn4mY lab44"
