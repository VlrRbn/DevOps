variable "aws_region" {
  type        = string
  description = "AWS region, e.g. eu-west-1"
  default     = "eu-west-1"
}

variable "project_name" {
  type        = string
  description = "Project prefix for resource names"
  default     = "lab44"
}

variable "environment" {
  type        = string
  description = "Environment dev/test/prod"
  default     = "dev"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Two public subnet CIDR blocks"
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
  description = "Two private subnet CIDR blocks"
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 1
    error_message = "At least one private subnet CIDR must be provided."
  }
}

variable "instance_type_web" {
  type        = string
  description = "EC2 instance type for web server"
  default     = "t3.micro"
}

variable "enable_full_ha" {
  type        = bool
  description = "Enable full HA setup. When true: multi-AZ + NAT gateways. When false: minimal/cheap mode."
  default     = false

  validation {
    condition     = !(var.enable_full_ha && !var.enable_nat)
    error_message = "enable_full_ha requires enable_nat to be true."
  }
}

variable "enable_nat" {
  type        = bool
  description = "If true: private subnets get outbound internet via NAT. If false: private has no internet."
  default     = false
}

variable "enable_ssm_vpc_endpoints" {
  type        = bool
  description = "Enable VPC Endpoints for SSM"
  default     = true
}

variable "enable_web_ssm" {
  type        = bool
  description = "If true, web instances are allowed to reach SSM VPC endpoints (debug mode). If false, only ssm-proxy is allowed"
  default     = false
}