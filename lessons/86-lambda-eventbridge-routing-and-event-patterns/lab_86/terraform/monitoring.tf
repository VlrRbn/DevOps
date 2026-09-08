resource "aws_cloudwatch_metric_alarm" "source_oldest_message" {
  for_each = local.consumers

  alarm_name          = "${local.resource_prefix}-${replace(each.key, "_", "-")}-source-oldest-message"
  alarm_description   = "${each.key} routing branch backlog age is above the lab threshold"
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

resource "aws_cloudwatch_metric_alarm" "processing_dead_letter_visible" {
  for_each = local.consumers

  alarm_name          = "${local.resource_prefix}-${replace(each.key, "_", "-")}-processing-dlq-visible"
  alarm_description   = "${each.key} consumer exhausted SQS processing retries"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.processing_dead_letter[each.key].name
  }
}

resource "aws_cloudwatch_metric_alarm" "delivery_dead_letter_visible" {
  for_each = local.consumers

  alarm_name          = "${local.resource_prefix}-${replace(each.key, "_", "-")}-delivery-dlq-visible"
  alarm_description   = "EventBridge exhausted delivery attempts for the ${each.key} target"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.delivery_dead_letter[each.key].name
  }
}

resource "aws_cloudwatch_metric_alarm" "eventbridge_failed_invocations" {
  for_each = local.consumers

  alarm_name          = "${local.resource_prefix}-${replace(each.key, "_", "-")}-eventbridge-failed-invocations"
  alarm_description   = "EventBridge failed to invoke the ${each.key} target"
  namespace           = "AWS/Events"
  metric_name         = "FailedInvocations"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    EventBusName = aws_cloudwatch_event_bus.orders.name
    RuleName     = aws_cloudwatch_event_rule.route[each.key].name
  }
}
