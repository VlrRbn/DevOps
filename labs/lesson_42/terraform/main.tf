provider "aws" {
  region = var.aws_region
}

module "network" {
  source = "./modules/network"

  aws_region            = var.aws_region
  project_name          = var.project_name
  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  allowed_ssh_cidr      = var.allowed_ssh_cidr
  key_name              = var.key_name
  instance_type_bastion = var.instance_type_bastion
  instance_type_web     = var.instance_type_web
  public_key            = var.public_key
  enable_full_ha        = var.enable_full_ha
  enable_nat            = var.enable_nat
  /*
  use_localstack        = var.use_localstack
  ami_id                = var.ami_id
  */

}
