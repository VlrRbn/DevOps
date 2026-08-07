output "aws_region" {
  description = "AWS Region used by the lab and CLI verification commands"
  value       = var.aws_region
}

output "function_name" {
  description = "Lambda SQS consumer function name"
  value       = aws_lambda_function.sqs_consumer.function_name
}

output "function_execution_role_arn" {
  description = "Role assumed by Lambda while consuming the source queue"
  value       = aws_iam_role.function_execution.arn
}

output "function_runtime_policy_name" {
  description = "Inline policy for logs and exact source-queue consumption"
  value       = aws_iam_role_policy.function_runtime_access.name
}

output "source_queue_url" {
  description = "URL used to send lab messages"
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

output "dead_letter_queue_arn" {
  description = "ARN configured in the source queue redrive policy"
  value       = aws_sqs_queue.dead_letter.arn
}

output "event_source_mapping_uuid" {
  description = "UUID of the SQS-to-Lambda event source mapping"
  value       = aws_lambda_event_source_mapping.source_queue.uuid
}

output "max_receive_count" {
  description = "Receive attempts before SQS moves a message to the DLQ"
  value       = var.max_receive_count
}

output "function_errors_alarm_name" {
  description = "CloudWatch alarm for whole Lambda invocation errors"
  value       = aws_cloudwatch_metric_alarm.function_errors.alarm_name
}

output "source_age_alarm_name" {
  description = "CloudWatch alarm for source queue processing delay"
  value       = aws_cloudwatch_metric_alarm.source_oldest_message.alarm_name
}

output "dlq_depth_alarm_name" {
  description = "CloudWatch alarm for visible DLQ messages"
  value       = aws_cloudwatch_metric_alarm.dead_letter_visible.alarm_name
}
