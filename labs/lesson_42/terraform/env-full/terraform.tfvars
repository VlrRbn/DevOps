aws_region   = "eu-west-1"
project_name = "lab42"
environment  = "full"

vpc_cidr = "10.30.0.0/16"

public_subnet_cidrs  = ["10.32.1.0/24", "10.32.2.0/24"]
private_subnet_cidrs = ["10.33.11.0/24", "10.33.12.0/24"]

allowed_ssh_cidr = "0.0.0.0/0" # WARNING need PUBLIC_IP/32

enable_full_ha = true
enable_nat     = true

key_name              = "lab40_terraform"
instance_type_bastion = "t3.micro"
instance_type_web     = "t3.micro"
public_key            = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMWsE+xq1dTRxdWIPtPlGqH6DgactNPMpZQeJlnZoI5M lab40"
