variable "aws_region" {
  type        = string
  description = "AWS region, e.g. eu-west-1"
  default     = "eu-west-1"
}

variable "project_name" {
  type        = string
  description = "Project prefix for resource names"
  default     = "lab40"
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
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "My public IP/CIDR for SSH to bastion (e.g. 203.0.113.10/32)"
  default     = "0.0.0.0/32" # WARNING
}

variable "key_name" {
  type        = string
  description = "SSH key pair name in AWS to use for EC2 instances"
  default     = "lab40-key"
}

variable "public_key" {
  type        = string
  description = "SSH public key"
}

variable "instance_type_bastion" {
  type        = string
  description = "EC2 instance type for bastion host"
  default     = "t3.micro"
}

variable "instance_type_web" {
  type        = string
  description = "EC2 instance type for web server"
  default     = "t3.micro"
}

/*
variable "use_localstack" {
  type    = bool
  default = false
}

variable "ami_id" {
  type    = string
  default = null
}
*/
