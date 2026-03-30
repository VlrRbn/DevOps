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

# ALB unhealthy hosts - safety critical signal.
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

  alarm_description = "ALB Unhealthy hosts - safety critical signal"

}

# ALB 5XX - safety critical signal.
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

  alarm_description = "ALB 5XX - safety critical signal"

}

# Target 5XX - safety critical signal.
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

  alarm_description = "Safety critical signal: backend 5xx regression"

}

# Target 5XX - release quality gate. Catch regressions early.
resource "aws_cloudwatch_metric_alarm" "release_5xx_gate" {
  alarm_name          = "${var.project_name}-release-target-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }

  alarm_description = "Release quality gate: backend 5xx regression"

}

# Target latency - release quality gate. Catch latency regressions early.
resource "aws_cloudwatch_metric_alarm" "latency_gate" {
  alarm_name          = "${var.project_name}-release-latency"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 0.5
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }

  alarm_description = "Release quality gate: backend latency regression"

}
