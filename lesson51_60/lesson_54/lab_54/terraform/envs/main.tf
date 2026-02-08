provider "aws" {
  region = var.aws_region

}

module "network" {
  source = "../modules/network"

  aws_region                     = var.aws_region
  project_name                   = var.project_name
  environment                    = var.environment
  vpc_cidr                       = var.vpc_cidr
  public_subnet_cidrs            = var.public_subnet_cidrs
  private_subnet_cidrs           = var.private_subnet_cidrs
  instance_type_web              = var.instance_type_web
  enable_full_ha                 = var.enable_full_ha
  enable_nat                     = var.enable_nat
  enable_ssm_vpc_endpoints       = var.enable_ssm_vpc_endpoints
  enable_web_ssm                 = var.enable_web_ssm
  web_ami_blue_id                = var.web_ami_blue_id
  web_ami_green_id               = var.web_ami_green_id
  ssm_proxy_ami_id               = var.ssm_proxy_ami_id
  traffic_weight_blue            = var.traffic_weight_blue
  traffic_weight_green           = var.traffic_weight_green
  blue_min_size                  = var.blue_min_size
  blue_max_size                  = var.blue_max_size
  blue_desired_capacity          = var.blue_desired_capacity
  green_min_size                 = var.green_min_size
  green_max_size                 = var.green_max_size
  green_desired_capacity         = var.green_desired_capacity
  tg_slow_start_seconds          = var.tg_slow_start_seconds
  health_check_healthy_threshold = var.health_check_healthy_threshold
}
