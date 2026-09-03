output "aws_region" {
  description = "AWS Region used by the lab"
  value       = var.aws_region
}

output "topic_arn" {
  description = "SNS topic ARN used by the publisher"
  value       = aws_sns_topic.orders.arn
}

output "topic_name" {
  description = "SNS topic name used by CloudWatch metrics"
  value       = aws_sns_topic.orders.name
}

output "function_names" {
  description = "Lambda function name keyed by consumer branch"
  value = {
    for consumer, function in aws_lambda_function.consumer :
    consumer => function.function_name
  }
}

output "source_queue_urls" {
  description = "Source queue URL keyed by consumer branch"
  value = {
    for consumer, queue in aws_sqs_queue.source :
    consumer => queue.url
  }
}

output "dead_letter_queue_urls" {
  description = "DLQ URL keyed by consumer branch"
  value = {
    for consumer, queue in aws_sqs_queue.dead_letter :
    consumer => queue.url
  }
}

output "subscription_arns" {
  description = "SNS subscription ARN keyed by consumer branch"
  value = {
    audit   = aws_sns_topic_subscription.audit.arn
    billing = aws_sns_topic_subscription.billing.arn
  }
}

output "billing_filter_policy" {
  description = "Decoded billing subscription filter policy"
  value       = jsondecode(aws_sns_topic_subscription.billing.filter_policy)
}

output "event_source_mapping_uuids" {
  description = "Lambda event source mapping UUID keyed by consumer branch"
  value = {
    for consumer, mapping in aws_lambda_event_source_mapping.source_queue :
    consumer => mapping.uuid
  }
}

output "alarm_names" {
  description = "CloudWatch alarm names for branch and SNS delivery signals"
  value = concat(
    [for alarm in aws_cloudwatch_metric_alarm.source_oldest_message : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.dead_letter_visible : alarm.alarm_name],
    [aws_cloudwatch_metric_alarm.sns_delivery_failures.alarm_name],
  )
}
