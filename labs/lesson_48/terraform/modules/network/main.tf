terraform {
  required_version = "~> 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

#--- Discover available AZs ---
data "aws_availability_zones" "available" {
  state = "available"
}

#--- Get the latest Ubuntu 24.04 AMI ---
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

#--- Derived subnet maps and helper lists ---
locals {
  az_letters = ["a", "b", "c", "d", "e", "f"]
  azs        = slice(data.aws_availability_zones.available.names, 0, max(length(var.public_subnet_cidrs), length(var.private_subnet_cidrs)))

  public_subnet_map = {
    for idx, cidr in var.public_subnet_cidrs :
    local.az_letters[idx] => { cidr = cidr, az = local.azs[idx] }
  }

  private_subnet_map = {
    for idx, cidr in var.private_subnet_cidrs :
    local.az_letters[idx] => { cidr = cidr, az = local.azs[idx] }
  }

  public_subnet_keys = sort(keys(local.public_subnet_map))

  private_subnet_keys = sort(keys(local.private_subnet_map))

  private_subnet_ids = [
    for key in sort(keys(aws_subnet.private_subnet)) :
    aws_subnet.private_subnet[key].id
  ]

  ssm_services = var.enable_ssm_vpc_endpoints ? toset(["ssm", "ssmmessages", "ec2messages"]) : toset([])

  # fixed the NAT logic single NAT vs per-AZ
  nat_keys = var.enable_nat ? (
    var.enable_full_ha ? local.public_subnet_keys :
    (length(local.public_subnet_keys) > 0 ? [local.public_subnet_keys[0]] : [])
  ) : []

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# --- VPC ---
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

# --- Public subnets (from CIDR list) ---
resource "aws_subnet" "public_subnet" {
  for_each = local.public_subnet_map

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-public_subnet-${each.key}"
    Tier = "public"
  })
}

# --- Private subnets (from CIDR list) ---
resource "aws_subnet" "private_subnet" {
  for_each = local.private_subnet_map

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${var.project_name}-private_subnet-${each.key}"
    Tier = "private"
  })
}

# ***** Security Groups (stateful L4) *****

# --- SSM Endpoints: allow HTTPS from VPC CIDR ---
resource "aws_security_group" "ssm_endpoint" {
  name        = "${var.project_name}-ssm_endpoint_sg"
  description = "Allow HTTPS from VPC CIDR to SSM Endpoint"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-ssm_endpoint_sg"
  })
}

# --- SSM Proxy: allow all outbound to reach internal ALB ---
resource "aws_security_group" "ssm_proxy" {
  name        = "${var.project_name}-ssm-proxy-sg"
  description = "Client SG used to reach internal ALB"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-ssm-proxy-sg"
  })
}

# --- Web: allow HTTP/HTTPS from VPC CIDR ---
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web_sg"
  description = "Web service access only"
  vpc_id      = aws_vpc.main.id

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

# --- ALB SG: allow HTTP/HTTPS from Internet ---
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb_sg"
  description = "ALB SG: inbound 80 only from ssm-proxy SG"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-alb_sg"
  })
}

resource "aws_security_group_rule" "alb_http_from_ssm_proxy" {
  type                     = "ingress"
  description              = "HTTP to internal ALB from SSM Proxy SG"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = aws_security_group.ssm_proxy.id

}

resource "aws_security_group_rule" "ssm_proxy_to_alb_80" {
  type                     = "egress"
  description              = "SSM proxy can reach ALB on 80 only"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ssm_proxy.id
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "ssm_proxy_https_out" {
  type              = "egress"
  description       = "Allow HTTPS egress for SSM via NAT"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.ssm_proxy.id
  cidr_blocks       = ["0.0.0.0/0"]
}

# --- Web: allow HTTP from ALB SG ---
resource "aws_security_group_rule" "web_from_alb" {
  type                     = "ingress"
  description              = "HTTP from ALB SG"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web.id
  source_security_group_id = aws_security_group.alb.id

}

# --- ALB Target Group for Web Instances ---
resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-web-tg"
  })

}

# --- ALB Target Group Attachments for both Web Instances ---
resource "aws_lb_target_group_attachment" "web_a" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web_a.id
  port             = 80

}

resource "aws_lb_target_group_attachment" "web_b" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web_b.id
  port             = 80

}

# --- Application Load Balancer ---
resource "aws_lb" "app" {
  name               = "${var.project_name}-app-alb"
  internal           = true
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb.id]
  subnets         = [for subnet in aws_subnet.private_subnet : subnet.id]

  tags = merge(local.tags, {
    Name = "${var.project_name}-app-alb"
  })

}

# --- ALB Listener for HTTP ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

}

# ***** Web: EC2 Private Subnet *****

# --- Create two web instances in two different private subnets ---
resource "aws_instance" "web_a" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_web
  subnet_id              = aws_subnet.private_subnet[local.private_subnet_keys[0]].id
  vpc_security_group_ids = [aws_security_group.web.id]

  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_instance_profile.name

  user_data                   = file("${path.module}/scripts/web-userdata.sh")
  user_data_replace_on_change = true

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-web-a"
    Role = "web"
  })
}

resource "aws_instance" "web_b" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_web
  subnet_id              = aws_subnet.private_subnet[local.private_subnet_keys[1]].id
  vpc_security_group_ids = [aws_security_group.web.id]

  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_instance_profile.name

  user_data                   = file("${path.module}/scripts/web-userdata.sh")
  user_data_replace_on_change = true

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-web-b"
    Role = "web"
  })

}

resource "aws_instance" "ssm_proxy" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_subnet[local.private_subnet_keys[0]].id
  vpc_security_group_ids = [aws_security_group.ssm_proxy.id]

  # SSH not allowed
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_instance_profile.name

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-ssm_proxy"
    Role = "ssm-proxy"
  })

}

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

# --- VPC Endpoints for SSM family services ---
resource "aws_vpc_endpoint" "ssm" {
  for_each          = local.ssm_services
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type = "Interface"

  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.ssm_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-ssm_vpc_endpoint-${each.key}"
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

# --- Associate Public Subnets with Public Route Table ---
resource "aws_route_table_association" "public_subnet_assoc" {
  for_each = aws_subnet.public_subnet

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rt.id
}

# --- Private Route Tables: 0.0.0.0/0 -> NAT (if enabled) ---
resource "aws_route_table" "private_rt" {
  for_each = local.private_subnet_map
  vpc_id   = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.enable_full_ha ? aws_nat_gateway.nat_gw[each.key].id : aws_nat_gateway.nat_gw[local.public_subnet_keys[0]].id
    }
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-private_rt-${each.key}"
  })
}

# --- Associate Private Subnets with Private Route Tables ---
resource "aws_route_table_association" "private_rt_assoc" {
  for_each = aws_subnet.private_subnet

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rt[each.key].id
}

# ***** NAT Gateway and EIP for Public Subnets (if enabled) *****

# --- EIP for NAT Gateway Public Subnet ---
resource "aws_eip" "nat" {
  for_each = toset(local.nat_keys)
  domain   = "vpc"

  tags = merge(local.tags, {
    Name = "${var.project_name}-nat_eip-${each.key}"
  })
}

# --- NAT Gateway in Public Subnet ---
resource "aws_nat_gateway" "nat_gw" {
  for_each = toset(local.nat_keys)

  subnet_id     = aws_subnet.public_subnet[each.key].id
  allocation_id = aws_eip.nat[each.key].id

  tags = merge(local.tags, {
    Name = "${var.project_name}-nat_gw-${each.key}"
  })

  depends_on = [
    aws_internet_gateway.igw,
    aws_route_table_association.public_subnet_assoc
  ]
}

# ***** Instances *****

# IAM Role and Instance Profile for SSM
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach the AmazonSSMManagedInstanceCore policy to the role
resource "aws_iam_role_policy_attachment" "ec2_ssm_role_attach" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create the ec2_ssm Instance Profile
resource "aws_iam_instance_profile" "ec2_ssm_instance_profile" {
  name = "${var.project_name}-ec2-ssm-instance-profile"
  role = aws_iam_role.ec2_ssm_role.name
}