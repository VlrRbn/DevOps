output "function_name" {
  description = "Lambda function name used by AWS CLI invocation commands"
  value       = aws_lambda_function.greeting.function_name
}

output "aws_region" {
  description = "AWS Region used by the lab and its CLI verification commands"
  value       = var.aws_region
}

output "function_execution_role_arn" {
  description = "Role assumed by the Lambda service during handler execution"
  value       = aws_iam_role.function_execution.arn
}

output "lambda_caller_role_arn" {
  description = "Role assumed by the operator to test Lambda invocation"
  value       = aws_iam_role.lambda_caller.arn
}

output "invoke_permission_mode" {
  description = "Active Lambda invocation authorization path"
  value       = var.invoke_permission_mode
}

output "caller_invoke_policy_name" {
  description = "Inline caller policy name in lambda_caller_identity_policy mode; null otherwise"
  value       = var.invoke_permission_mode == "lambda_caller_identity_policy" ? aws_iam_role_policy.lambda_caller_invoke_access[0].name : null
}

output "function_logs_policy_name" {
  description = "Inline logs policy attached to the function execution role"
  value       = aws_iam_role_policy.function_log_access.name
}
