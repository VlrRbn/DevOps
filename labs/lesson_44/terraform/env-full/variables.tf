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

variable "allowed_ssh_cidr" {
  type = string
}

variable "ssh_key_name" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "instance_type_bastion" {
  type = string
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
