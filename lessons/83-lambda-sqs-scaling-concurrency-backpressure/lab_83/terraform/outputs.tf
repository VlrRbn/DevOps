output "aws_region" {
  description = "AWS Region used by the lab and CLI verification commands"
  value       = var.aws_region
}

output "function_name" {
  description = "Lambda SQS worker function name"
  value       = aws_lambda_function.worker.function_name
}

output "source_queue_url" {
  description = "URL used to submit burst work items"
  value       = aws_sqs_queue.source.url
}

output "source_queue_arn" {
  description = "ARN consumed by the Lambda event source mapping"
  value       = aws_sqs_queue.source.arn
}

output "dead_letter_queue_url" {
  description = "URL used to inspect exhausted messages"
  value       = aws_sqs_queue.dead_letter.url
}

output "event_source_mapping_uuid" {
  description = "UUID used to inspect event source scaling configuration"
  value       = aws_lambda_event_source_mapping.source_queue.uuid
}

output "event_source_maximum_concurrency" {
  description = "Concurrency cap applied to this SQS event source mapping"
  value       = var.event_source_maximum_concurrency
}

output "function_reserved_concurrency" {
  description = "Optional function-wide reserved concurrency; null means unreserved"
  value       = var.function_reserved_concurrency
}

output "function_throttles_alarm_name" {
  description = "CloudWatch alarm for Lambda throttling"
  value       = aws_cloudwatch_metric_alarm.function_throttles.alarm_name
}

output "source_age_alarm_name" {
  description = "CloudWatch alarm for source queue processing delay"
  value       = aws_cloudwatch_metric_alarm.source_oldest_message.alarm_name
}

output "dlq_depth_alarm_name" {
  description = "CloudWatch alarm for visible DLQ messages"
  value       = aws_cloudwatch_metric_alarm.dead_letter_visible.alarm_name
}
