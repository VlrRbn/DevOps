variable "ssm_ami_name_prefix" {
  type    = string
  default = "lab63-ssm-proxy"
}

source "amazon-ebs" "ssm_proxy" {
  region        = var.aws_region
  instance_type = var.instance_type
  ssh_username  = var.ssh_username

  ami_name = "${var.ssm_ami_name_prefix}-${var.build_id}-${formatdate("YYYYMMDD-hhmm", timestamp())}"

  source_ami_filter {
    filters     = local.ubuntu_noble_ami_filters
    owners      = local.ubuntu_ami_owners
    most_recent = true
  }

  tags = merge(local.common_tags, {
    Role    = "ssm-proxy"
    BuildId = var.build_id
  })
}

build {
  sources = ["source.amazon-ebs.ssm_proxy"]

  provisioner "shell" {
    script          = "scripts/install-ssm-agent.sh"
    execute_command = "sudo -n bash '{{.Path}}'"
  }

  provisioner "shell" {
    script          = "scripts/install-wrk.sh"
    execute_command = "sudo -n BUILD_ID='${var.build_id}' bash '{{.Path}}'"
  }
}
