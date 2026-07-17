output "function_name" {
  description = "Lambda function name used by AWS CLI invocation commands"
  value       = aws_lambda_function.hello.function_name
}

output "aws_region" {
  description = "AWS Region used by the lab and its CLI verification commands"
  value       = var.aws_region
}

output "execution_role_arn" {
  description = "IAM role assumed by the Lambda service during execution"
  value       = aws_iam_role.lambda.arn
}

output "log_group_name" {
  description = "CloudWatch Logs group for function runtime logs"
  value       = aws_cloudwatch_log_group.function.name
}
