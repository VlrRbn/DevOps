resource "aws_cloudwatch_metric_alarm" "api_server_errors" {
  alarm_name          = "${local.resource_prefix}-api-5xx"
  alarm_description   = "HTTP API server failures, including integration permission errors"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.http.id
    Stage = aws_apigatewayv2_stage.default.name
  }
}

resource "aws_cloudwatch_metric_alarm" "function_errors" {
  alarm_name          = "${local.resource_prefix}-function-errors"
  alarm_description   = "Lambda failures; controlled HTTP 4xx responses do not increment this metric"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.http.function_name
  }
}
