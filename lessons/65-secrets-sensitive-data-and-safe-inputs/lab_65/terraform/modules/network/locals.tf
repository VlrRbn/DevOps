#--- Discover available AZs ---
data "aws_availability_zones" "available" {
  state = "available"
}

#--- Derived subnet maps and helper lists ---
locals {
  az_letters = ["a", "b", "c", "d", "e", "f"]
  azs        = slice(data.aws_availability_zones.available.names, 0, max(length(var.public_subnet_cidrs), length(var.private_subnet_cidrs)))

  public_subnet_map = {
    for idx, cidr in var.public_subnet_cidrs :
    local.az_letters[idx] => { cidr = cidr, az = local.azs[idx] }
  }

  private_subnet_map = {
    for idx, cidr in var.private_subnet_cidrs :
    local.az_letters[idx] => { cidr = cidr, az = local.azs[idx] }
  }

  private_subnet_ids = [
    for key in sort(keys(aws_subnet.private_subnet)) :
    aws_subnet.private_subnet[key].id
  ]

  ssm_services = var.enable_ssm_vpc_endpoints ? toset(["ssm", "ssmmessages", "ec2messages"]) : toset([])

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}
