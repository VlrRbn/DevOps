provider "aws" {
  region = var.aws_region

}

module "network" {
  source = "../modules/network"

  aws_region               = var.aws_region
  project_name             = var.project_name
  environment              = var.environment
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_subnet_cidrs     = var.private_subnet_cidrs
  instance_type_web        = var.instance_type_web
  enable_full_ha           = var.enable_full_ha
  enable_nat               = var.enable_nat
  enable_ssm_vpc_endpoints = var.enable_ssm_vpc_endpoints
  enable_web_ssm           = var.enable_web_ssm
  web_ami_id               = var.web_ami_id
  ssm_proxy_ami_id         = var.ssm_proxy_ami_id
}
