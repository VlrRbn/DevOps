locals {
  ubuntu_noble_ami_filters = {
    name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
    virtualization-type = "hvm"
    root-device-type    = "ebs"
  }

  ubuntu_ami_owners = ["099720109477"] # Canonical

  common_tags = {
    Project = "DevOps"
    Lesson  = "56"
  }
}
