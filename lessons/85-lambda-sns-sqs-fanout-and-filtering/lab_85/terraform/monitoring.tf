resource "aws_cloudwatch_metric_alarm" "source_oldest_message" {
  for_each = local.consumers

  alarm_name          = "${local.resource_prefix}-${each.key}-source-oldest-message"
  alarm_description   = "${each.key} branch backlog age is above the lab threshold"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 120
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.source[each.key].name
  }
}

resource "aws_cloudwatch_metric_alarm" "dead_letter_visible" {
  for_each = local.consumers

  alarm_name          = "${local.resource_prefix}-${each.key}-dlq-visible"
  alarm_description   = "${each.key} branch has at least one message in its DLQ"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dead_letter[each.key].name
  }
}

resource "aws_cloudwatch_metric_alarm" "sns_delivery_failures" {
  alarm_name          = "${local.resource_prefix}-sns-delivery-failures"
  alarm_description   = "SNS failed to deliver at least one notification"
  namespace           = "AWS/SNS"
  metric_name         = "NumberOfNotificationsFailed"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    TopicName = aws_sns_topic.orders.name
  }
}
