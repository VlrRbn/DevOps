output "aws_region" {
  description = "AWS Region used by the lab and CLI verification commands"
  value       = var.aws_region
}

output "function_name" {
  description = "Lambda FIFO worker function name"
  value       = aws_lambda_function.worker.function_name
}

output "source_queue_url" {
  description = "FIFO queue URL used by the sender scripts"
  value       = aws_sqs_queue.source.url
}

output "source_queue_name" {
  description = "FIFO source queue name used for CloudWatch metrics"
  value       = aws_sqs_queue.source.name
}

output "dead_letter_queue_url" {
  description = "FIFO DLQ URL used for non-destructive inspection"
  value       = aws_sqs_queue.dead_letter.url
}

output "event_source_mapping_uuid" {
  description = "UUID used to inspect FIFO event source configuration"
  value       = aws_lambda_event_source_mapping.source_queue.uuid
}

output "event_source_maximum_concurrency" {
  description = "Source-level maximum concurrency for the FIFO mapping"
  value       = var.event_source_maximum_concurrency
}

output "function_reserved_concurrency" {
  description = "Optional function reservation; null means unreserved"
  value       = var.function_reserved_concurrency
}

output "function_throttles_alarm_name" {
  description = "CloudWatch alarm for Lambda throttling"
  value       = aws_cloudwatch_metric_alarm.function_throttles.alarm_name
}

output "source_age_alarm_name" {
  description = "CloudWatch alarm for blocked or delayed FIFO work"
  value       = aws_cloudwatch_metric_alarm.source_oldest_message.alarm_name
}

output "dlq_depth_alarm_name" {
  description = "CloudWatch alarm for visible FIFO DLQ messages"
  value       = aws_cloudwatch_metric_alarm.dead_letter_visible.alarm_name
}
