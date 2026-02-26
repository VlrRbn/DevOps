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
