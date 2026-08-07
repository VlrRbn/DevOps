# Partial batch failures are returned as a successful Lambda response, so they
# do not necessarily increment Errors. This alarm catches whole-invocation
# failures such as an invalid top-level SQS event contract.
resource "aws_cloudwatch_metric_alarm" "function_errors" {
  alarm_name          = local.function_errors_alarm_name
  alarm_description   = "Whole Lambda batch invocation failed"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.sqs_consumer.function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "source_oldest_message" {
  alarm_name          = local.source_age_alarm_name
  alarm_description   = "Source queue processing is falling behind"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = aws_sqs_queue.source.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 120
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "dead_letter_visible" {
  alarm_name          = local.dlq_depth_alarm_name
  alarm_description   = "At least one message is visible in the SQS DLQ"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dead_letter.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}
