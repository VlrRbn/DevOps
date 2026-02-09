aws_region   = "eu-west-1"
project_name = "lab55"
environment  = "full"

vpc_cidr = "10.30.0.0/16"

public_subnet_cidrs  = ["10.30.1.0/24", "10.30.2.0/24"]
private_subnet_cidrs = ["10.30.11.0/24", "10.30.12.0/24"]


enable_full_ha                 = true
enable_nat                     = true
enable_ssm_vpc_endpoints       = true
enable_web_ssm                 = true
web_ami_id                     = "ami-08dbb3eb37b020b9b"
ssm_proxy_ami_id               = "ami-0b46d0ccaa378571d"
web_min_size                   = 2
web_max_size                   = 2
web_desired_capacity           = 2
asg_min_healthy_percentage     = 50
asg_instance_warmup_seconds    = 180
tg_slow_start_seconds          = 60
health_check_healthy_threshold = 2

instance_type_web = "t3.micro"
