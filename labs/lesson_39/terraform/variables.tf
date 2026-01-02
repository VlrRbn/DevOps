variable "aws_region" {
  type        = string
  description = "AWS region, e.g. eu-west-1"
  default     = "us-west-1"
}

variable "project_name" {
  type        = string
  description = "Project prefix for resource names"
  default     = "lab39"
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
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Two private subnet CIDR blocks"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "My public IP/CIDR for SSH to bastion (e.g. 203.0.113.10/32)"
  default     = "0.0.0.0/32"
}