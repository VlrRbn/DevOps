terraform {
  required_version = "~> 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

/*
data "aws_ami" "ubuntu" {
  count       = var.use_localstack ? 0 : 1
  most_recent = true
  owners      = ["099720109477"] # Canonical (AWS)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
*/

resource "aws_key_pair" "lab40" {
  key_name   = var.key_name
  public_key = var.public_key

  tags = merge(local.tags, {
    Name = "${var.project_name}-keypair"
  })
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))

  /*
  ubuntu = {
    id = var.use_localstack ? var.ami_id : data.aws_ami.ubuntu[0].id
  }
*/

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-vpc"
  })

}

# --- Internet Gateway (internet for public) ---

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-igw"
  })

}

# --- Public subnets (2 AZ) ---

resource "aws_subnet" "public_subnet" {

  for_each = {
    a = { cidr = var.public_subnet_cidrs[0], az = local.azs[0] }
    b = { cidr = var.public_subnet_cidrs[1], az = local.azs[1] }
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-public_subnet-${each.key}"
    Tier = "public"
  })
}

# --- Private subnets (2 AZ) ---

resource "aws_subnet" "private_subnet" {

  for_each = {
    a = { cidr = var.private_subnet_cidrs[0], az = local.azs[0] }
    b = { cidr = var.private_subnet_cidrs[1], az = local.azs[1] }
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${var.project_name}-private_subnet-${each.key}"
    Tier = "private"
  })
}

# --- Public Route Table: 0.0.0.0/0 -> IGW ---

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-public_rt"
  })
}

resource "aws_route_table_association" "public_subnet_assoc" {
  for_each = aws_subnet.public_subnet

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rt.id
}

# --- Private Route Tables: 0.0.0.0/0 -> NAT ---

resource "aws_route_table" "private_rt" {
  vpc_id   = aws_vpc.main.id
  for_each = aws_subnet.private_subnet

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw[each.key].id
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-private_rt-${each.key}"
  })
}

resource "aws_route_table_association" "private_rt_assoc" {
  for_each = aws_subnet.private_subnet

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rt[each.key].id
}

# --- NAT Gateway and EIP for Public Subnets ---

# 1) EIP for NAT Gateway Public Subnet
resource "aws_eip" "nat" {
  for_each = aws_subnet.public_subnet
  domain   = "vpc"

  tags = merge(local.tags, {
    Name = "${var.project_name}-nat_eip-${each.key}"
  })
}

# 2) NAT Gateway in Public Subnet
resource "aws_nat_gateway" "nat_gw" {
  for_each = aws_subnet.public_subnet

  subnet_id     = each.value.id
  allocation_id = aws_eip.nat[each.key].allocation_id

  tags = merge(local.tags, {
    Name = "${var.project_name}-nat_gw-${each.key}"
  })

  depends_on = [
    aws_internet_gateway.igw,
    aws_route_table_association.public_subnet_assoc
  ]
}

# ***** Security Groups (stateful L4) *****

# --- Bastion: SSH from my IP only ---

resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion_sg"
  description = "SSH from my IP only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from allowed IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-bastion_sg"
  })
}

# --- Bastion: EC2 Public Subnet ---

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_bastion
  subnet_id                   = aws_subnet.public_subnet["a"].id
  key_name                    = aws_key_pair.lab40.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-bastion"
    Role = "bastion"
  })
}

/*
resource "aws_instance" "bastion" {
  ami                         = local.ubuntu.id
  instance_type               = var.instance_type_bastion
  subnet_id                   = aws_subnet.public_subnet["a"].id
  key_name                    = aws_key_pair.lab40.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-bastion"
    Role = "bastion"
  })
}
*/

# --- Web: allow 80/443 from anywhere (lab), SSH only from the bastion SG ---

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web_sg"
  description = "Allow HTTP/S from anywhere, SSH from Bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP 80 from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS 443 from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-web_sg"
  })
}

# --- Web: EC2 Private Subnet ---

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_web
  subnet_id                   = aws_subnet.private_subnet["a"].id
  key_name                    = aws_key_pair.lab40.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = false

  user_data = file("${path.module}/scripts/web-userdata.sh")

  tags = merge(local.tags, {
    Name = "${var.project_name}-web"
    Role = "web"
  })
}

/*
resource "aws_instance" "web" {
  ami                         = local.ubuntu.id
  instance_type               = var.instance_type_web
  subnet_id                   = aws_subnet.private_subnet["a"].id
  key_name                    = aws_key_pair.lab40.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = false

  user_data = file("${path.module}/scripts/web-userdata.sh")

  tags = merge(local.tags, {
    Name = "${var.project_name}-web"
    Role = "web"
  })
}
*/

# --- DB: allow only from Web SG ---

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db_sg"
  description = "Allow DB from Web SG only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from Web SG"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, {
    Name = "${var.project_name}-db_sg"
  })
}
