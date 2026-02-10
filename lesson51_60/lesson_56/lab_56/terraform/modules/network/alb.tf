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
