variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string

  validation {
    condition     = var.environment == "dev"
    error_message = "This root module accepts only environment = dev."
  }
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "instance_type_web" {
  type    = string
  default = "t3.micro"
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "enable_ssm_vpc_endpoints" {
  type    = bool
  default = true
}

variable "enable_web_ssm" {
  type    = bool
  default = false
}

variable "web_ami_id" {
  type = string
}

variable "web_min_size" {
  type = number
}

variable "web_max_size" {
  type = number
}

variable "web_desired_capacity" {
  type = number
}

variable "asg_min_healthy_percentage" {
  type    = number
  default = 50
}

variable "asg_instance_warmup_seconds" {
  type    = number
  default = 120
}

variable "asg_checkpoint_delay_seconds" {
  type    = number
  default = 360
}

variable "tg_slow_start_seconds" {
  type    = number
  default = 60
}

variable "health_check_healthy_threshold" {
  type    = number
  default = 2
}

variable "ssm_proxy_ami_id" {
  type = string
}

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "github_apply_environment" {
  type = string
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub Actions OIDC provider ARN. Leave empty only when this env should create it."
  type        = string
  default     = ""
}

variable "tf_state_bucket_name" {
  type = string
}

variable "tf_state_key" {
  type = string

  validation {
    condition     = var.tf_state_key == "lab76/dev/full/terraform.tfstate"
    error_message = "This root module accepts only tf_state_key = \"lab76/dev/full/terraform.tfstate\"."
  }
}

variable "demo_api_token_parameter_name" {
  type = string
}

variable "demo_app_secret_name" {
  type = string
}
