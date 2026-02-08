variable "aws_region" {
  type        = string
  description = "AWS region, e.g. eu-west-1"
  default     = "eu-west-1"
}

variable "project_name" {
  type        = string
  description = "Project prefix for resource names"
  default     = "lab55"
}

variable "environment" {
  type        = string
  description = "Environment name used for tags (dev/test/prod, etc.)"
  default     = "dev"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDR blocks (1+; 2+ required for full HA)"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 1
    error_message = "At least one public subnet CIDR must be provided."
  }

  validation {
    condition     = !(var.enable_full_ha && length(var.public_subnet_cidrs) < 2)
    error_message = "For full HA, at least two public subnets are required."
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
    condition     = !(var.enable_full_ha && length(var.private_subnet_cidrs) > length(var.public_subnet_cidrs))
    error_message = "For full HA, the number of private subnets must not exceed public subnets."
  }
}

variable "instance_type_web" {
  type        = string
  description = "EC2 instance type for web server"
  default     = "t3.micro"
}

variable "enable_full_ha" {
  type        = bool
  description = "Use one NAT gateway per public subnet (requires enable_nat). When false: single NAT gateway."
  default     = false

  validation {
    condition     = !(var.enable_full_ha && !var.enable_nat)
    error_message = "enable_full_ha requires enable_nat to be true."
  }
}

variable "enable_nat" {
  type        = bool
  description = "If true: private subnets get outbound internet via NAT. If false: no internet egress."
  default     = false
}

variable "enable_ssm_vpc_endpoints" {
  type        = bool
  description = "Create SSM interface VPC endpoints (ssm, ssmmessages, ec2messages)."
  default     = true
}

variable "enable_web_ssm" {
  type        = bool
  description = "If true, web instances can reach SSM VPC endpoints (debug). If false, only ssm-proxy is allowed."
  default     = false
}

variable "web_ami_id" {
  type        = string
  description = "Baked web AMI used by the single rolling ASG fleet"
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
}

variable "web_min_size" {
  type        = number
  description = "ASG minimum size for the rolling web fleet"
  default     = 2
}

variable "web_max_size" {
  type        = number
  description = "ASG maximum size for the rolling web fleet"
  default     = 4
}

variable "web_desired_capacity" {
  type        = number
  description = "ASG desired capacity for the rolling web fleet"
  default     = 2
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
  default     = 180

  validation {
    condition     = var.asg_instance_warmup_seconds >= 30
    error_message = "asg_instance_warmup_seconds must be at least 30."
  }
}

variable "ssm_proxy_ami_id" {
  type        = string
  description = "AMI for the SSM proxy (defaults to web_ami_id when null)"
  default     = null
}
