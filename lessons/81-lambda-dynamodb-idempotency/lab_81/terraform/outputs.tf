output "aws_region" {
  description = "AWS Region used by the lab and CLI verification commands"
  value       = var.aws_region
}

output "function_name" {
  description = "Lambda function name used by invocation commands"
  value       = aws_lambda_function.idempotent_worker.function_name
}

output "function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.idempotent_worker.arn
}

output "function_execution_role_arn" {
  description = "Role assumed by Lambda while the handler runs"
  value       = aws_iam_role.function_execution.arn
}

output "function_runtime_policy_name" {
  description = "Inline policy for logs and idempotency item operations"
  value       = aws_iam_role_policy.function_runtime_access.name
}

output "idempotency_table_name" {
  description = "DynamoDB table that stores claims and completed results"
  value       = aws_dynamodb_table.idempotency.name
}

output "claim_ttl_seconds" {
  description = "Configured lifetime of an IN_PROGRESS claim"
  value       = var.claim_ttl_seconds
}

output "record_ttl_seconds" {
  description = "Configured retention of a COMPLETED idempotency result"
  value       = var.record_ttl_seconds
}

output "function_errors_alarm_name" {
  description = "CloudWatch alarm for handler errors"
  value       = aws_cloudwatch_metric_alarm.function_errors.alarm_name
}
