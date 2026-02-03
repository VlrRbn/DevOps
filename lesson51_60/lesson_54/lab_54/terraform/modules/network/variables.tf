variable "aws_region" {
  type        = string
  description = "AWS region, e.g. eu-west-1"
  default     = "eu-west-1"
}

variable "project_name" {
  type        = string
  description = "Project prefix for resource names"
  default     = "lab54"
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
  description = "Baked web AMI from Packer"
}

variable "ssm_proxy_ami_id" {
  type        = string
  description = "Optional AMI for the SSM proxy (defaults to web_ami_id when null)"
  default     = null
}
