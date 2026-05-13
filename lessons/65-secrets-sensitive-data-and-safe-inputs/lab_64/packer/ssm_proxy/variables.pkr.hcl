variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "ssh_username" {
  type    = string
  default = "ubuntu"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "build_id" {
  # Example values: 64-proxy, 64-wrk.
  type    = string
  default = "64-proxy"
}
