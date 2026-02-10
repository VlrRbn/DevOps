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

  private_subnet_ids = [
    for key in sort(keys(aws_subnet.private_subnet)) :
    aws_subnet.private_subnet[key].id
  ]

  ssm_services = var.enable_ssm_vpc_endpoints ? toset(["ssm", "ssmmessages", "ec2messages"]) : toset([])

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# VPC for all subnets and resources.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-vpc"
  })

}

# Internet gateway for public subnet internet access.
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-igw"
  })

}

# Public subnets with public IPs on launch.
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

# Private subnets without public IPs.
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

# SG for SSM interface endpoints; allow HTTPS from proxy (and optional web).
resource "aws_security_group" "ssm_endpoint" {
  name        = "${var.project_name}-ssm_endpoint_sg"
  description = "Allow HTTPS to SSM Interface Endpoints"
  vpc_id      = aws_vpc.main.id

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

# SG for SSM proxy instance used for port-forwarding to internal ALB.
resource "aws_security_group" "ssm_proxy" {
  name        = "${var.project_name}-ssm-proxy-sg"
  description = "Client SG used to reach internal ALB"
  vpc_id      = aws_vpc.main.id

  # Egress to internal ALB only.
  egress {
    description = "SSM proxy can reach ALB on 80 only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [
      aws_security_group.alb.id
    ]
  }

  # DNS (UDP) to VPC resolver.
  egress {
    description = "DNS (UDP) to VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["${cidrhost(var.vpc_cidr, 2)}/32"]
  }

  # DNS (TCP) to VPC resolver.
  egress {
    description = "DNS (TCP) to VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["${cidrhost(var.vpc_cidr, 2)}/32"]
  }

  # HTTPS to private SSM interface endpoint ENIs within VPC CIDR.
  dynamic "egress" {
    for_each = var.enable_ssm_vpc_endpoints ? [1] : []
    content {
      description = "HTTPS to SSM interface endpoints only"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      security_groups = [
        aws_security_group.ssm_endpoint.id
      ]
    }
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-ssm-proxy-sg"
  })
}

# SG for web instances; ingress is defined by separate rules.
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

# SG for internal ALB; ingress is defined by separate rules.
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

# Allow HTTP from SSM proxy to the internal ALB.
resource "aws_security_group_rule" "alb_http_from_ssm_proxy" {
  type                     = "ingress"
  description              = "HTTP to internal ALB from SSM Proxy SG"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = aws_security_group.ssm_proxy.id

}

# Allow HTTPS from SSM proxy to SSM interface endpoints SG.
resource "aws_security_group_rule" "ssm_endpoint_https_from_proxy" {
  count                    = var.enable_ssm_vpc_endpoints ? 1 : 0
  type                     = "ingress"
  description              = "HTTPS from SSM Proxy SG"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ssm_endpoint.id
  source_security_group_id = aws_security_group.ssm_proxy.id
}

# Optional: allow HTTPS from web SG to SSM endpoints when web SSM is enabled.
resource "aws_security_group_rule" "ssm_endpoint_https_from_web" {
  count                    = var.enable_ssm_vpc_endpoints && var.enable_web_ssm ? 1 : 0
  type                     = "ingress"
  description              = "HTTPS from web SG"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ssm_endpoint.id
  source_security_group_id = aws_security_group.web.id
}

# Allow HTTP from ALB to web instances.
resource "aws_security_group_rule" "web_from_alb" {
  type                     = "ingress"
  description              = "HTTP from ALB SG"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web.id
  source_security_group_id = aws_security_group.alb.id

}

# ***** Load Balancer *****

# Single target group for the rolling fleet behind the ALB.
resource "aws_lb_target_group" "web" {
  name       = "${var.project_name}-web-tg"
  port       = 80
  protocol   = "HTTP"
  vpc_id     = aws_vpc.main.id
  slow_start = var.tg_slow_start_seconds

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = 2
  }

  tags = merge(local.tags, {
    Name  = "${var.project_name}-web-tg"
    Fleet = "primary"
  })

}

# Internal application load balancer across private subnets.
resource "aws_lb" "app" {
  name               = "${var.project_name}-app-alb"
  internal           = true
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb.id]
  subnets         = local.private_subnet_ids

  tags = merge(local.tags, {
    Name = "${var.project_name}-app-alb"
  })

}

# HTTP listener forwarding to web target group.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

}

# ***** Compute (EC2) *****

# Web instance template for Auto Scaling Group.
resource "aws_launch_template" "web" {
  name_prefix            = "${var.project_name}-web-"
  image_id               = var.web_ami_id
  instance_type          = var.instance_type_web
  update_default_version = true

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.web.id]
  }

  dynamic "iam_instance_profile" {
    for_each = var.enable_web_ssm ? [1] : []
    content {
      name = aws_iam_instance_profile.ec2_ssm_instance_profile.name
    }

  }

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.tags, {
      Name  = "${var.project_name}-web"
      Role  = "web"
      Fleet = "primary"
    })
  }
}

# Single ASG fleet updated via Instance Refresh.
resource "aws_autoscaling_group" "web" {
  name             = "${var.project_name}-web-asg"
  min_size         = var.web_min_size
  max_size         = var.web_max_size
  desired_capacity = var.web_desired_capacity

  vpc_zone_identifier = local.private_subnet_ids

  health_check_type         = "ELB"
  health_check_grace_period = 90

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }

  target_group_arns = [aws_lb_target_group.web.arn]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = var.asg_min_healthy_percentage
      instance_warmup        = var.asg_instance_warmup_seconds
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Role"
    value               = "web"
    propagate_at_launch = true
  }

  tag {
    key                 = "Version"
    value               = "rolling"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling policy (target tracking) to maintain average CPU at 50%.
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${var.project_name}-web-cpu-target-policy"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration { # SLA: keep average CPU around 50%
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50.0
  }

}

# ***** Monitoring (CloudWatch alarms) *****

# ALB 5XX - critical signal.
resource "aws_cloudwatch_metric_alarm" "alb_5xx_critical" {
  alarm_name          = "${var.project_name}-alb-5xx-critical"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }

  alarm_description = "ALB 5XX - critical signal"
}

# Target 5XX - critical signal.
resource "aws_cloudwatch_metric_alarm" "target_5xx_critical" {
  alarm_name          = "${var.project_name}-target-5xx-critical"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }

  alarm_description = "Target 5XX (app errors behind ALB) - critical signal"

}

# ALB unhealthy hosts - critical signal.
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy" {
  alarm_name          = "${var.project_name}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }

  alarm_description = "ALB Unhealthy hosts - critical signal"

}

# SSM proxy instance for port forwarding to internal ALB. (Access tool via SSM Session Manager.)
resource "aws_instance" "ssm_proxy" {
  ami                    = var.ssm_proxy_ami_id
  instance_type          = "t3.micro"
  subnet_id              = local.private_subnet_ids[0]
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

# SG for DB access (only from web SG).
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

# SSM interface endpoints in private subnets.
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

# Public route table with default route to IGW.
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

# Associate public subnets with public route table.
resource "aws_route_table_association" "public_subnet_assoc" {
  for_each = aws_subnet.public_subnet

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rt.id
}

# Private route tables without internet default route.
resource "aws_route_table" "private_rt" {
  for_each = local.private_subnet_map
  vpc_id   = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-private_rt-${each.key}"
  })
}

# Associate private subnets with private route tables.
resource "aws_route_table_association" "private_rt_assoc" {
  for_each = aws_subnet.private_subnet

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rt[each.key].id
}

# ***** IAM for SSM *****

# IAM role for SSM managed instances.
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

# Attach AmazonSSMManagedInstanceCore to the role.
resource "aws_iam_role_policy_attachment" "ec2_ssm_role_attach" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile for EC2 SSM role.
resource "aws_iam_instance_profile" "ec2_ssm_instance_profile" {
  name = "${var.project_name}-ec2-ssm-instance-profile"
  role = aws_iam_role.ec2_ssm_role.name
}
