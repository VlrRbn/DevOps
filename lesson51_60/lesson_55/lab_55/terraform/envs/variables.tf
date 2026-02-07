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

variable "web_ami_blue_id" {
  type = string
}

variable "web_ami_green_id" {
  type = string
}

variable "traffic_weight_blue" {
  type    = number
  default = 100
}

variable "traffic_weight_green" {
  type    = number
  default = 0
}

variable "blue_min_size" {
  type    = number
  default = 2
}

variable "blue_max_size" {
  type    = number
  default = 4
}

variable "blue_desired_capacity" {
  type    = number
  default = 2
}

variable "green_min_size" {
  type    = number
  default = 0
}

variable "green_max_size" {
  type    = number
  default = 2
}

variable "tg_slow_start_seconds" {
  type    = number
  default = 60
}

variable "health_check_healthy_threshold" {
  type    = number
  default = 2
}

variable "green_desired_capacity" {
  type    = number
  default = 0
}

variable "ssm_proxy_ami_id" {
  type    = string
  default = null
}
