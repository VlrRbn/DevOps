terraform {
  # Backend values come from backend.hcl during init, not from Terraform variables.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

module "network" {
  source = "../../modules/network"

  aws_region                     = var.aws_region
  project_name                   = var.project_name
  environment                    = var.environment
  vpc_cidr                       = var.vpc_cidr
  public_subnet_cidrs            = var.public_subnet_cidrs
  private_subnet_cidrs           = var.private_subnet_cidrs
  instance_type_web              = var.instance_type_web
  common_tags                    = var.common_tags
  enable_ssm_vpc_endpoints       = var.enable_ssm_vpc_endpoints
  enable_web_ssm                 = var.enable_web_ssm
  web_ami_id                     = var.web_ami_id
  ssm_proxy_ami_id               = var.ssm_proxy_ami_id
  web_min_size                   = var.web_min_size
  web_max_size                   = var.web_max_size
  web_desired_capacity           = var.web_desired_capacity
  asg_min_healthy_percentage     = var.asg_min_healthy_percentage
  asg_instance_warmup_seconds    = var.asg_instance_warmup_seconds
  asg_checkpoint_delay_seconds   = var.asg_checkpoint_delay_seconds
  tg_slow_start_seconds          = var.tg_slow_start_seconds
  health_check_healthy_threshold = var.health_check_healthy_threshold
  github_owner                   = var.github_owner
  github_repo                    = var.github_repo
  github_branch                  = var.github_branch
  github_apply_environment       = var.github_apply_environment
  github_oidc_provider_arn       = var.github_oidc_provider_arn
  tf_state_bucket_name           = var.tf_state_bucket_name
  tf_state_key                   = var.tf_state_key
  demo_api_token_parameter_name  = var.demo_api_token_parameter_name
  demo_app_secret_name           = var.demo_app_secret_name
}
