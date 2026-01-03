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

variable "key_name" {
  type = string
}

variable "public_key_path" {
  type = string
}

variable "instance_type_bastion" {
  type = string
}

variable "instance_type_web" {
  type = string
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
