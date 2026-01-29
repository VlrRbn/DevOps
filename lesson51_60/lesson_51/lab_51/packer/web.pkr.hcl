variable "ami_name_prefix" {
  type    = string
  default = "lab50-web"
}

source "amazon-ebs" "web" {
  region        = var.aws_region
  instance_type = var.instance_type
  ssh_username  = var.ssh_username

  ami_name = "${var.ami_name_prefix}-${formatdate("YYYYMMDD-hhmm", timestamp())}"

  source_ami_filter {
    filters     = local.ubuntu_noble_ami_filters
    owners      = local.ubuntu_ami_owners
    most_recent = true
  }

  tags = merge(local.common_tags, {
    Role = "web"
  })
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
    script = "scripts/setup-render.sh"
    environment_vars = [
      "AMI_VERSION=${var.ami_name_prefix}",
      "BUILD_TIME=${timestamp()}"
    ]
  }
}
