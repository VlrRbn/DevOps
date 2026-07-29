resource "aws_cloudwatch_metric_alarm" "function_errors" {
  alarm_name          = local.function_errors_alarm_name
  alarm_description   = "Lesson 80 Lambda handler errors detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.async_worker.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "destination_delivery_failures" {
  alarm_name          = local.destination_delivery_failures_alarm_name
  alarm_description   = "Lambda could not deliver an asynchronous failure record"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DestinationDeliveryFailures"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.async_worker.function_name
  }
}
