aws_region   = "eu-west-1"
project_name = "lab62"
environment  = "full"

vpc_cidr = "10.30.0.0/16"

public_subnet_cidrs  = ["10.30.1.0/24", "10.30.2.0/24"]
private_subnet_cidrs = ["10.30.11.0/24", "10.30.12.0/24"]


enable_ssm_vpc_endpoints = true
enable_web_ssm           = true
web_ami_id               = "ami-0ff02c319e33722b1"
# ami-0ff02c319e33722b1
# ami-0358ca03959d7b689
ssm_proxy_ami_id               = "ami-055a5cb906b0088b0"
web_min_size                   = 2
web_max_size                   = 2
web_desired_capacity           = 2
asg_min_healthy_percentage     = 50
asg_instance_warmup_seconds    = 120
asg_checkpoint_delay_seconds   = 360
tg_slow_start_seconds          = 60
health_check_healthy_threshold = 2

instance_type_web = "t3.micro"
