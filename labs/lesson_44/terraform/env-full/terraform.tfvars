aws_region   = "eu-west-1"
project_name = "lab44"
environment  = "full"

vpc_cidr = "10.30.0.0/16"

public_subnet_cidrs  = ["10.30.1.0/24", "10.30.2.0/24"]
private_subnet_cidrs = ["10.30.11.0/24", "10.30.12.0/24"]


enable_full_ha = true
enable_nat     = true
enable_ssm     = true

instance_type_web     = "t3.micro"
