aws_region   = "eu-west-1"
project_name = "lab55"
environment  = "full"

vpc_cidr = "10.30.0.0/16"

public_subnet_cidrs  = ["10.30.1.0/24", "10.30.2.0/24"]
private_subnet_cidrs = ["10.30.11.0/24", "10.30.12.0/24"]


enable_full_ha           = true
enable_nat               = true
enable_ssm_vpc_endpoints = true
enable_web_ssm           = true
web_ami_blue_id          = "ami-04444dcc97616d8ef"
web_ami_green_id         = "ami-0190de6443ebc0d94"
ssm_proxy_ami_id         = "ami-0895efd813ec18f9a"
traffic_weight_blue      = 100
traffic_weight_green     = 0
blue_min_size            = 2
blue_max_size            = 4
blue_desired_capacity    = 2
green_min_size           = 1
green_max_size           = 4
green_desired_capacity   = 1    # Start with green ASG scaled down to 1 for testing
tg_slow_start_seconds    = 60
health_check_healthy_threshold = 2

instance_type_web = "t3.micro"
