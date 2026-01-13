aws_region   = "eu-west-1"
project_name = "lab44"
environment  = "cheap"

# Keep it simple: still use /16 for VPC, but only use 1 subnet per tier
vpc_cidr = "10.40.0.0/16"

# Only 1 public + 1 private subnet for cheap setup
public_subnet_cidrs  = ["10.40.1.0/24"]
private_subnet_cidrs = ["10.40.11.0/24"]

# No NAT at all is the cheapest
# enable_nat          = false
# enable_full_ha      = false
enable_nat = true

instance_type_web     = "t3.micro"
