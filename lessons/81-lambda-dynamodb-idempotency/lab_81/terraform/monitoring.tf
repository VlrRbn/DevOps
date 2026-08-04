resource "aws_cloudwatch_metric_alarm" "function_errors" {
  alarm_name          = local.function_errors_alarm_name
  alarm_description   = "Lambda errors, including active idempotency conflicts and invalid events"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.idempotent_worker.function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}
