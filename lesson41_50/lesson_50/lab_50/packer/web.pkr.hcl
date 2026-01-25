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
  default = "lab50-web"
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
    Lesson  = "50"
  }
}

build {
  sources = ["source.amazon-ebs.web"]

  provisioner "shell" {
    script          = "scripts/install-nginx.sh"
    execute_command = "sudo -n bash '{{.Path}}'"
  }

  provisioner "shell" {
    script          = "scripts/web-content.sh"
    execute_command = "sudo -n bash '{{.Path}}'"
  }

  provisioner "file" {
    source      = "scripts/render-index.sh"
    destination = "/tmp/render-index.sh"
  }

  provisioner "file" {
    source      = "scripts/render-index.service"
    destination = "/tmp/render-index.service"
  }

  provisioner "shell" {
    script = "scripts/setup-renderer.sh"
    environment_vars = [
      "AMI_VERSION=${var.ami_name_prefix}",
      "BUILD_TIME=${timestamp()}"
    ]
  }
}