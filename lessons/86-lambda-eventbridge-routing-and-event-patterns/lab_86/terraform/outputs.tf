output "aws_region" {
  description = "AWS Region used by the lab"
  value       = var.aws_region
}

output "event_bus_name" {
  description = "Custom EventBridge bus name used by the publisher"
  value       = aws_cloudwatch_event_bus.orders.name
}

output "event_source" {
  description = "Stable EventBridge source value expected by the rules"
  value       = var.event_source
}

output "rule_names" {
  description = "EventBridge rule name keyed by routing branch"
  value = {
    for consumer, rule in aws_cloudwatch_event_rule.route :
    consumer => rule.name
  }
}

output "event_patterns" {
  description = "Decoded EventBridge pattern keyed by routing branch"
  value = {
    for consumer, rule in aws_cloudwatch_event_rule.route :
    consumer => jsondecode(rule.event_pattern)
  }
}

output "function_names" {
  description = "Lambda function name keyed by routing branch"
  value = {
    for consumer, function in aws_lambda_function.consumer :
    consumer => function.function_name
  }
}

output "source_queue_urls" {
  description = "Source queue URL keyed by routing branch"
  value = {
    for consumer, queue in aws_sqs_queue.source :
    consumer => queue.url
  }
}

output "processing_dead_letter_queue_urls" {
  description = "Consumer-processing DLQ URL keyed by routing branch"
  value = {
    for consumer, queue in aws_sqs_queue.processing_dead_letter :
    consumer => queue.url
  }
}

output "delivery_dead_letter_queue_urls" {
  description = "EventBridge-target delivery DLQ URL keyed by routing branch"
  value = {
    for consumer, queue in aws_sqs_queue.delivery_dead_letter :
    consumer => queue.url
  }
}

output "event_source_mapping_uuids" {
  description = "Lambda event source mapping UUID keyed by routing branch"
  value = {
    for consumer, mapping in aws_lambda_event_source_mapping.source_queue :
    consumer => mapping.uuid
  }
}

output "alarm_names" {
  description = "CloudWatch alarm names for routing, queue, and DLQ signals"
  value = concat(
    [for alarm in aws_cloudwatch_metric_alarm.source_oldest_message : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.processing_dead_letter_visible : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.delivery_dead_letter_visible : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.eventbridge_failed_invocations : alarm.alarm_name],
  )
}
