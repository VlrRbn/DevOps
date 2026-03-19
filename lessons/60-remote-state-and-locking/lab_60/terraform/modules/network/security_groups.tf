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
