output "function_name" {
  description = "Lambda function name used by AWS CLI invocation commands"
  value       = aws_lambda_function.async_worker.function_name
}

output "aws_region" {
  description = "AWS Region used by the lab and its CLI verification commands"
  value       = var.aws_region
}

output "function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.async_worker.arn
}

output "function_execution_role_arn" {
  description = "Role assumed by the Lambda service during handler execution"
  value       = aws_iam_role.function_execution.arn
}

output "function_runtime_policy_name" {
  description = "Inline policy that permits logs and failure destination delivery"
  value       = aws_iam_role_policy.function_runtime_access.name
}

output "failure_queue_url" {
  description = "SQS URL that receives failed asynchronous invocation records"
  value       = aws_sqs_queue.lambda_failure_destination.url
}

output "failure_queue_arn" {
  description = "SQS ARN configured as the Lambda failure destination"
  value       = aws_sqs_queue.lambda_failure_destination.arn
}

output "maximum_retry_attempts" {
  description = "Configured number of retries after the first failed attempt"
  value       = aws_lambda_function_event_invoke_config.async_worker.maximum_retry_attempts
}

output "maximum_event_age_in_seconds" {
  description = "Configured maximum asynchronous event age"
  value       = aws_lambda_function_event_invoke_config.async_worker.maximum_event_age_in_seconds
}

output "function_errors_alarm_name" {
  description = "CloudWatch alarm for Lambda handler errors"
  value       = aws_cloudwatch_metric_alarm.function_errors.alarm_name
}

output "destination_delivery_failure_alarm_name" {
  description = "CloudWatch alarm for failed destination delivery"
  value       = aws_cloudwatch_metric_alarm.destination_delivery_failures.alarm_name
}
