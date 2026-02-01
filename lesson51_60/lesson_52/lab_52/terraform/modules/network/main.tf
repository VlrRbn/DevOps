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

  ingress {
    description = "HTTPS from SSM Proxy SG (web-flag)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = concat(
      [aws_security_group.ssm_proxy.id],
      var.enable_web_ssm ? [aws_security_group.web.id] : []
    )
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

# SG for SSM proxy instance used for port-forwarding to internal ALB.
resource "aws_security_group" "ssm_proxy" {
  name        = "${var.project_name}-ssm-proxy-sg"
  description = "Client SG used to reach internal ALB"
  vpc_id      = aws_vpc.main.id

  # Restrict ingress to explicit rules below.
  ingress = []
  # Restrict egress to explicit rules below.
  egress = []

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

# Limit SSM proxy egress to ALB:80.
resource "aws_security_group_rule" "ssm_proxy_to_alb_80" {
  type                     = "egress"
  description              = "SSM proxy can reach ALB on 80 only"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ssm_proxy.id
  source_security_group_id = aws_security_group.alb.id
}

# Allow SSM HTTPS via NAT when VPC endpoints are disabled.
resource "aws_security_group_rule" "ssm_proxy_https_out" {
  count             = var.enable_ssm_vpc_endpoints ? 0 : 1
  type              = "egress"
  description       = "Allow HTTPS egress for SSM via NAT"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.ssm_proxy.id
  cidr_blocks       = ["0.0.0.0/0"]
}

# Allow DNS (UDP) to the VPC resolver.
resource "aws_security_group_rule" "ssm_proxy_dns_udp" {
  type              = "egress"
  description       = "DNS to VPC resolver"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  security_group_id = aws_security_group.ssm_proxy.id
  cidr_blocks       = ["${cidrhost(var.vpc_cidr, 2)}/32"]
}

# Allow DNS (TCP) to the VPC resolver.
resource "aws_security_group_rule" "ssm_proxy_dns_tcp" {
  type              = "egress"
  description       = "DNS (TCP) to VPC resolver"
  from_port         = 53
  to_port           = 53
  protocol          = "tcp"
  security_group_id = aws_security_group.ssm_proxy.id
  cidr_blocks       = ["${cidrhost(var.vpc_cidr, 2)}/32"]
}

# Allow HTTPS from proxy to SSM endpoints (no NAT needed).
resource "aws_security_group_rule" "ssm_proxy_https_to_vpc" {
  count                    = var.enable_ssm_vpc_endpoints ? 1 : 0
  type                     = "egress"
  description              = "HTTPS from proxy to VPC via SSM endpoints, NAT not required"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ssm_proxy.id
  source_security_group_id = aws_security_group.ssm_endpoint.id
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

# Target group for web instances behind the ALB.
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
  name_prefix   = "${var.project_name}-web-"
  image_id      = var.web_ami_id
  instance_type = var.instance_type_web

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
      Name = "${var.project_name}-web"
      Role = "web"
    })
  }
}

# Auto Scaling Group for web instances.
resource "aws_autoscaling_group" "web" {
  name             = "${var.project_name}-web-asg"
  min_size         = 2
  max_size         = 4
  desired_capacity = 2

  vpc_zone_identifier = local.private_subnet_ids

  health_check_type         = "ELB"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.web.arn]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 180
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Role"
    value               = "web"
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

/*
# CloudWatch alarms + Step Scaling policies (disabled; using Target Tracking instead).

# CloudWatch alarm for high CPU (over 70% for 2 consecutive periods).
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-web-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70.0

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  alarm_description = "Alarm when CPU exceeds 70%"

  alarm_actions = [aws_autoscaling_policy.scale_out_step.arn]

}

# CloudWatch alarm for low CPU (below 30% for 5 consecutive periods).
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-web-cpu-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 30.0

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  alarm_description = "Alarm when CPU drops below 30%"

  alarm_actions = [aws_autoscaling_policy.scale_in_step.arn]

}

# Auto Scaling policy (step scaling) to add 1 instance on high CPU alarm.
resource "aws_autoscaling_policy" "scale_out_step" {
  name                   = "${var.project_name}-web-scale-out-step"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "StepScaling"

  adjustment_type           = "ChangeInCapacity"
  estimated_instance_warmup = 180

  step_adjustment {
    metric_interval_lower_bound = 0
    scaling_adjustment          = 1
  }
  
}

# Auto Scaling policy (step scaling) to remove 1 instance on low CPU alarm.
resource "aws_autoscaling_policy" "scale_in_step" {
  name                   = "${var.project_name}-web-scale-in-step"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "StepScaling"

  adjustment_type           = "ChangeInCapacity"
  estimated_instance_warmup = 180

  step_adjustment {
    metric_interval_upper_bound = 0
    scaling_adjustment          = -1
  }
  
}

# Scheduled action to scale down at 22:00 UTC (Ireland local time).
resource "aws_autoscaling_schedule" "scale_down_night" {
  scheduled_action_name  = "${var.project_name}-web-scale-down-night"
  autoscaling_group_name = aws_autoscaling_group.web.name
  desired_capacity       = 1
  min_size               = 1
  max_size               = 2
  start_time             = "2026-01-30T22:00:00Z"
  end_time               = "2027-12-31T06:00:00Z"
  recurrence             = "0 22 * * *" # Every day at 22:00 UTC (Ireland local time)
  
}

# Scheduled action to scale up at 06:00 UTC (Ireland local time).
resource "aws_autoscaling_schedule" "scale_up_morning" {
  scheduled_action_name  = "${var.project_name}-web-scale-up-morning"
  autoscaling_group_name = aws_autoscaling_group.web.name
  desired_capacity       = 2
  min_size               = 2
  max_size               = 4
  start_time             = "2026-01-31T06:00:00Z"
  end_time               = "2027-12-31T07:00:00Z"
  recurrence             = "0 6 * * *" # Every day at 06:00 UTC (Ireland local time)
  
}
*/

# SSM proxy instance for port forwarding to internal ALB. (Access tool via SSM Session Manager.)
resource "aws_instance" "ssm_proxy" {
  ami                    = coalesce(var.ssm_proxy_ami_id, var.web_ami_id)
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

# Private route tables with optional default route to NAT.
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

# Associate private subnets with private route tables.
resource "aws_route_table_association" "private_rt_assoc" {
  for_each = aws_subnet.private_subnet

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rt[each.key].id
}

# ***** NAT Gateway and EIP for Public Subnets (if enabled) *****

# Elastic IPs for NAT gateways.
resource "aws_eip" "nat" {
  for_each = toset(local.nat_keys)
  domain   = "vpc"

  tags = merge(local.tags, {
    Name = "${var.project_name}-nat_eip-${each.key}"
  })
}

# NAT gateways in public subnets.
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
