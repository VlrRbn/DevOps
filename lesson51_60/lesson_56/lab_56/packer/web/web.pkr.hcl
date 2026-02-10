variable "ami_name_prefix" {
  type    = string
  default = "lab56-web"
}

source "amazon-ebs" "web" {
  region        = var.aws_region
  instance_type = var.instance_type
  ssh_username  = var.ssh_username

  # Put build_id into AMI name to make refresh/rollback traceable in AWS console.
  ami_name = "${var.ami_name_prefix}-${var.build_id}-${formatdate("YYYYMMDD-hhmm", timestamp())}"

  source_ami_filter {
    filters     = local.ubuntu_noble_ami_filters
    owners      = local.ubuntu_ami_owners
    most_recent = true
  }

  tags = merge(local.common_tags, {
    Role    = "web"
    Version = var.ami_version
    # Duplicate deployment identity in tags for quick filtering/auditing.
    BuildId = var.build_id
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
      # BUILD_ID is baked into /etc/web-build/build_id inside the AMI.
      "BUILD_ID=${var.build_id}",
      "BUILD_TIME=${timestamp()}"
    ]
  }
}
