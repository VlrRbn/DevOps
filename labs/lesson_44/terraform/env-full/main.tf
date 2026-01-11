provider "aws" {
  region = var.aws_region
}

module "network" {
  source = "../modules/network"

  aws_region            = var.aws_region
  project_name          = var.project_name
  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  allowed_ssh_cidr      = var.allowed_ssh_cidr
  ssh_key_name          = var.ssh_key_name
  ssh_public_key        = var.ssh_public_key
  instance_type_bastion = var.instance_type_bastion
  instance_type_web     = var.instance_type_web
  enable_full_ha        = var.enable_full_ha
  enable_nat            = var.enable_nat

}
