resource "aws_apigatewayv2_api" "http" {
  name          = "${local.resource_prefix}-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "function" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.http.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

resource "aws_apigatewayv2_route" "http" {
  for_each = local.routes

  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "${each.value.method} /${each.value.path}"
  authorization_type = each.value.authorization
  target             = "integrations/${aws_apigatewayv2_integration.function.id}"
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${local.resource_prefix}-http-api"
  retention_in_days = 7
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = local.stage_name
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.throttle_rate_limit
    throttling_burst_limit = var.throttle_burst_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      request_id        = "$context.requestId"
      route             = "$context.routeKey"
      status            = "$context.status"
      response_length   = "$context.responseLength"
      integration_error = "$context.integrationErrorMessage"
    })
  }
}
