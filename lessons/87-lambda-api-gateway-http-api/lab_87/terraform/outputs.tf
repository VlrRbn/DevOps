output "aws_region" {
  description = "Region used for API requests and signing"
  value       = var.aws_region
}

output "api_endpoint" {
  description = "HTTPS endpoint; the $default stage needs no URL suffix"
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "api_id" {
  description = "HTTP API identifier for inspection with aws apigatewayv2"
  value       = aws_apigatewayv2_api.http.id
}

output "function_name" {
  description = "Lambda function behind the HTTP API"
  value       = aws_lambda_function.http.function_name
}

output "log_group_names" {
  description = "Separate API access and Lambda application log groups"
  value = {
    api      = aws_cloudwatch_log_group.api_access.name
    function = aws_cloudwatch_log_group.function.name
  }
}

output "caller_policy_example" {
  description = "Reference identity policy for POST /quotes; not attached automatically"
  value = {
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "execute-api:Invoke"
      Resource = "${aws_apigatewayv2_api.http.execution_arn}/${local.stage_name}/POST/quotes"
    }]
  }
}
