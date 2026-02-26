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
