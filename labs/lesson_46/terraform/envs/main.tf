provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {

      Project     = var.project_name
      Environment = var.environment
    }
  }
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

}
