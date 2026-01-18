variable "aws_region" {
  type = string
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
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
  type = string
}

variable "enable_full_ha" {
  type    = bool
  default = false
}

variable "enable_nat" {
  type    = bool
  default = false
}

variable "enable_ssm_vpc_endpoints" {
  type    = bool
  default = true
}

variable "enable_web_ssm" {
  type    = bool
  default = false
}