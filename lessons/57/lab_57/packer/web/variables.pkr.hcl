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

variable "ami_version" {
  type    = string
  default = "blue"
}

variable "build_id" {
  # Deployment identity shown on the page (examples: 56-01, 56-02).
  type    = string
  default = "56-01"
}
