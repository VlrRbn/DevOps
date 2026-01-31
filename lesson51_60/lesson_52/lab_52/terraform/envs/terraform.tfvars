aws_region   = "eu-west-1"
project_name = "lab50"
environment  = "full"

vpc_cidr = "10.30.0.0/16"

public_subnet_cidrs  = ["10.30.1.0/24", "10.30.2.0/24"]
private_subnet_cidrs = ["10.30.11.0/24", "10.30.12.0/24"]


enable_full_ha           = true
enable_nat               = true
enable_ssm_vpc_endpoints = true
enable_web_ssm           = true
web_ami_id               = "ami-065a809321bb347d7"
ssm_proxy_ami_id         = "ami-0895efd813ec18f9a"

instance_type_web = "t3.micro"
