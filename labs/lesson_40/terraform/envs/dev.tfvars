aws_region           = "eu-west-1"
project_name         = "lab40"
environment          = "dev"
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
allowed_ssh_cidr     = "0.0.0.0/0"    # WARNING
