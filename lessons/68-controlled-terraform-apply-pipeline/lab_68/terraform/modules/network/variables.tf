variable "aws_region" {
  type        = string
  description = "AWS region, e.g. eu-west-1"
  default     = "eu-west-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must look like a valid AWS region, for example eu-west-1."
  }
}

variable "project_name" {
  type        = string
  description = "Project prefix for resource names"
  default     = "lab68"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "project_name must be lowercase kebab-style, start with a letter, and be 3-31 characters."
  }
}

variable "environment" {
  type        = string
  description = "Environment name used for tags (dev/test/prod, etc.)"
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.environment))
    error_message = "environment must be lowercase, start with a letter, and be 2-21 characters."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDR blocks. The internal ALB design expects at least two AZs."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "public_subnet_cidrs must contain at least two CIDRs."
  }

  validation {
    condition     = length(var.public_subnet_cidrs) <= 6
    error_message = "public_subnet_cidrs must contain at most six CIDRs because this module maps subnet keys a-f."
  }

  validation {
    condition     = length(distinct(var.public_subnet_cidrs)) == length(var.public_subnet_cidrs)
    error_message = "public_subnet_cidrs must not contain duplicate CIDRs."
  }

  validation {
    condition     = alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every public_subnet_cidrs entry must be a valid IPv4 CIDR block."
  }

}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDR blocks (minimum 2 for ASG spread)"
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least two private subnet CIDRs are required for the web instances."
  }

  validation {
    condition     = length(var.private_subnet_cidrs) <= 6
    error_message = "private_subnet_cidrs must contain at most six CIDRs because this module maps subnet keys a-f."
  }

  validation {
    condition     = length(distinct(var.private_subnet_cidrs)) == length(var.private_subnet_cidrs)
    error_message = "private_subnet_cidrs must not contain duplicate CIDRs."
  }

  validation {
    condition     = alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every private_subnet_cidrs entry must be a valid IPv4 CIDR block."
  }

}

variable "instance_type_web" {
  type        = string
  description = "EC2 instance type for web server"
  default     = "t3.micro"
}

variable "enable_ssm_vpc_endpoints" {
  type        = bool
  description = "Create private interface VPC endpoints for Session Manager and runtime secret reads."
  default     = true
}

variable "enable_web_ssm" {
  type        = bool
  description = "If true, web instances can reach private interface endpoints (debug). If false, only ssm-proxy is allowed."
  default     = false
}

variable "web_ami_id" {
  type        = string
  description = "Baked web AMI used by the single rolling ASG fleet"

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.web_ami_id))
    error_message = "web_ami_id must look like an AWS AMI ID, for example ami-0123456789abcdef0."
  }
}

variable "tg_slow_start_seconds" {
  type        = number
  description = "Target group slow start duration in seconds (30-900)"
  default     = 60

  validation {
    condition     = var.tg_slow_start_seconds >= 30 && var.tg_slow_start_seconds <= 900
    error_message = "tg_slow_start_seconds must be between 30 and 900."
  }
}

variable "health_check_healthy_threshold" {
  type        = number
  description = "Number of consecutive successful checks before considering target healthy"
  default     = 2

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "health_check_healthy_threshold must be between 2 and 10."
  }
}

variable "web_min_size" {
  type        = number
  description = "ASG minimum size for the rolling web fleet"
  default     = 2

  validation {
    condition     = var.web_min_size >= 1
    error_message = "web_min_size must be at least 1."
  }
}

variable "web_max_size" {
  type        = number
  description = "ASG maximum size for the rolling web fleet"
  default     = 4

  validation {
    condition     = var.web_max_size >= 1
    error_message = "web_max_size must be at least 1."
  }
}

variable "web_desired_capacity" {
  type        = number
  description = "ASG desired capacity for the rolling web fleet"
  default     = 2

  validation {
    condition     = var.web_desired_capacity >= var.web_min_size && var.web_desired_capacity <= var.web_max_size
    error_message = "web_desired_capacity must be between web_min_size and web_max_size."
  }
}

variable "asg_min_healthy_percentage" {
  type        = number
  description = "Minimum healthy percentage during ASG instance refresh"
  default     = 50

  validation {
    condition     = var.asg_min_healthy_percentage >= 0 && var.asg_min_healthy_percentage <= 100
    error_message = "asg_min_healthy_percentage must be between 0 and 100."
  }
}

variable "asg_instance_warmup_seconds" {
  type        = number
  description = "Warmup time in seconds for ASG instance refresh"
  default     = 120

  validation {
    condition     = var.asg_instance_warmup_seconds >= 30
    error_message = "asg_instance_warmup_seconds must be at least 30."
  }
}

variable "asg_checkpoint_delay_seconds" {
  type        = number
  description = "Checkpoint delay in seconds for ASG instance refresh"
  default     = 180

  validation {
    condition     = var.asg_checkpoint_delay_seconds >= 30
    error_message = "asg_checkpoint_delay_seconds must be at least 30."
  }
}

variable "ssm_proxy_ami_id" {
  type        = string
  description = "AMI for the SSM proxy (must be explicit to avoid coupling with web_ami_id)"
  nullable    = false

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.ssm_proxy_ami_id))
    error_message = "ssm_proxy_ami_id must look like an AWS AMI ID, for example ami-0123456789abcdef0."
  }
}

variable "common_tags" {
  type        = map(string)
  description = "Optional caller-provided tags. Required governance tags are merged after this map and cannot be overridden."
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.common_tags : length(trimspace(k)) > 0 && length(trimspace(v)) > 0])
    error_message = "common_tags must not contain empty keys or empty values."
  }

  validation {
    condition = alltrue([
      for k in keys(var.common_tags) :
      !contains(["Project", "Environment", "ManagedBy", "Lesson"], k)
    ])
    error_message = "common_tags must not set reserved keys: Project, Environment, ManagedBy, Lesson."
  }
}

variable "github_owner" {
  description = "GitHub organization or username"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.github_owner))
    error_message = "github_owner must contain only letters, numbers, and hyphens."
  }
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must contain only letters, numbers, dots, underscores, and hyphens."
  }
}

variable "github_branch" {
  description = "GitHub branch allowed to assume this role"
  type        = string
  default     = "main"

  validation {
    condition     = length(trimspace(var.github_branch)) > 0
    error_message = "github_branch must not be empty."
  }
}

variable "tf_state_bucket_name" {
  description = "Remote state S3 bucket used by the Terraform CI plan role"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.tf_state_bucket_name))
    error_message = "tf_state_bucket_name must look like a valid S3 bucket name."
  }
}

variable "tf_state_key" {
  description = "Remote state object key used by the Terraform CI plan role"
  type        = string
  default     = "lab68/dev/full/terraform.tfstate"

  validation {
    condition     = length(trimspace(var.tf_state_key)) > 0 && !startswith(var.tf_state_key, "/")
    error_message = "tf_state_key must be a non-empty relative S3 object key."
  }
}

variable "demo_api_token_parameter_name" {
  type        = string
  description = "SSM SecureString name that the EC2 runtime role may read. Terraform should not read its plaintext value."
  default     = "/devops/lab68/demo/api-token"

  validation {
    condition     = startswith(var.demo_api_token_parameter_name, "/")
    error_message = "demo_api_token_parameter_name must be an absolute SSM parameter path starting with /."
  }
}

variable "demo_app_secret_name" {
  type        = string
  description = "Secrets Manager secret name that the EC2 runtime role may read. Terraform references metadata only."
  default     = "/devops/lab68/demo/app-secret"

  validation {
    condition     = startswith(var.demo_app_secret_name, "/")
    error_message = "demo_app_secret_name must be an absolute Secrets Manager path starting with /."
  }
}
