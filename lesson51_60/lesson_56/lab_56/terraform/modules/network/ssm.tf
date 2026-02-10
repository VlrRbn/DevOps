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
