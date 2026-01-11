aws_region   = "eu-west-1"
project_name = "lab44"
environment  = "full"

vpc_cidr = "10.30.0.0/16"

public_subnet_cidrs  = ["10.30.1.0/24", "10.30.2.0/24"]
private_subnet_cidrs = ["10.30.11.0/24", "10.30.12.0/24"]

allowed_ssh_cidr = "0.0.0.0/32" # WARNING need PUBLIC_IP/32 --- curl -4 ifconfig.me

enable_full_ha = true
enable_nat     = true

ssh_key_name          = "lab44_terraform"
instance_type_bastion = "t3.micro"
instance_type_web     = "t3.micro"
ssh_public_key        = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKWfwU+2WOaa5CeywI+J4TX8jzqam+QgiUPNerdBn4mY lab44" # ~/.ssh/
