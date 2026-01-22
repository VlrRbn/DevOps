packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.10"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "ami_name_prefix" {
  type    = string
  default = "lab49-web"
}

source "amazon-ebs" "web" {
  region        = var.aws_region
  instance_type = "t3.micro"
  ssh_username  = "ubuntu"

  ami_name = "${var.ami_name_prefix}-${formatdate("YYYYMMDD-hhmm", timestamp())}"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  tags = {
    Project = "DevOps"
    Role    = "web"
    Lesson  = "49"
  }
}

build {
  sources = ["source.amazon-ebs.web"]

  provisioner "shell" {
  inline = [
    "whoami",
    "id",
    "sudo -n true && echo SUDO_OK || (echo NO_SUDO; exit 1)"
    ]
  }

  provisioner "shell" {
    script = "scripts/install-nginx.sh"
    execute_command = "sudo -n bash '{{.Path}}'"
  }

  provisioner "shell" {
    script = "scripts/web-content.sh"
    execute_command = "sudo -n bash '{{.Path}}'"
  }
}