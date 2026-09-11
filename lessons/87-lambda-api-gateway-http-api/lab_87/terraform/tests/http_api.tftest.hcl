mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

# The mock provider also mocks aws_iam_policy_document data sources. Supply
# valid documents so resource schema validation and permission assertions stay meaningful.
override_data {
  target          = data.aws_iam_policy_document.function_execution_trust
  override_during = plan
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowLambdaServiceToAssumeRole\",\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"}}]}"
  }
}

override_resource {
  target          = aws_apigatewayv2_api.http
  override_during = plan
  values = {
    id            = "testapi123"
    execution_arn = "arn:aws:execute-api:eu-west-1:123456789012:testapi123"
  }
}

override_resource {
  target          = aws_iam_role.function_execution
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/lab87-dev-http-function-execution-role" }
}

override_resource {
  target          = aws_cloudwatch_log_group.function
  override_during = plan
  values          = { arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/lambda/lab87-dev-http-function" }
}

run "quote_route_requires_iam_while_health_is_public" {
  command = plan
  assert {
    condition = (
      length(aws_apigatewayv2_route.http) == 2 &&
      aws_apigatewayv2_route.http["health"].route_key == "GET /health" &&
      aws_apigatewayv2_route.http["health"].authorization_type == "NONE" &&
      aws_apigatewayv2_route.http["quotes"].route_key == "POST /quotes" &&
      aws_apigatewayv2_route.http["quotes"].authorization_type == "AWS_IAM"
    )
    error_message = "Keep exactly two explicit routes; quotes must require IAM."
  }
}

run "http_proxy_contract_and_timeout_order" {
  command = plan
  assert {
    condition = (
      aws_apigatewayv2_api.http.protocol_type == "HTTP" &&
      aws_apigatewayv2_integration.function.integration_type == "AWS_PROXY" &&
      aws_apigatewayv2_integration.function.payload_format_version == "2.0" &&
      aws_apigatewayv2_integration.function.integration_method == "POST" &&
      aws_lambda_function.http.timeout * 1000 < aws_apigatewayv2_integration.function.timeout_milliseconds
    )
    error_message = "Preserve payload v2 and a Lambda timeout below the integration timeout."
  }
}

run "gateway_permissions_are_scoped_to_exact_routes" {
  command = plan
  assert {
    condition = alltrue([
      for key, route in local.routes :
      aws_lambda_permission.api_route[key].source_arn == "arn:aws:execute-api:eu-west-1:123456789012:testapi123/$default/${route.method}/${route.path}" &&
      aws_lambda_permission.api_route[key].source_account == "123456789012" &&
      aws_lambda_permission.api_route[key].principal == "apigateway.amazonaws.com" &&
      aws_lambda_permission.api_route[key].action == "lambda:InvokeFunction"
    ])
    error_message = "Gateway permission must be scoped by API, stage, method, path and account."
  }
}

run "runtime_role_has_only_log_permissions" {
  command = plan
  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.function_logs.policy).Statement) == 1 &&
      toset(jsondecode(aws_iam_role_policy.function_logs.policy).Statement[0].Action) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) &&
      jsondecode(aws_iam_role_policy.function_logs.policy).Statement[0].Resource == "${aws_cloudwatch_log_group.function.arn}:*" &&
      jsondecode(aws_iam_role.function_execution.assume_role_policy).Statement[0].Principal.Service == "lambda.amazonaws.com"
    )
    error_message = "The calculation needs no SQS, DynamoDB, or wildcard runtime access."
  }
}

run "caller_example_allows_only_quote_invocation" {
  command = plan
  assert {
    condition = (
      output.caller_policy_example.Statement[0].Action == "execute-api:Invoke" &&
      output.caller_policy_example.Statement[0].Resource == "arn:aws:execute-api:eu-west-1:123456789012:testapi123/$default/POST/quotes"
    )
    error_message = "Caller IAM permissions must point to execute-api, not Lambda."
  }
}

run "logs_throttles_and_error_metrics_are_configured" {
  command = plan
  assert {
    condition = (
      aws_apigatewayv2_stage.default.name == "$default" &&
      aws_apigatewayv2_stage.default.default_route_settings[0].throttling_rate_limit == 5 &&
      aws_apigatewayv2_stage.default.default_route_settings[0].throttling_burst_limit == 10 &&
      jsondecode(aws_apigatewayv2_stage.default.access_log_settings[0].format).request_id == "$context.requestId" &&
      jsondecode(aws_apigatewayv2_stage.default.access_log_settings[0].format).integration_error == "$context.integrationErrorMessage" &&
      aws_cloudwatch_metric_alarm.api_server_errors.metric_name == "5xx" &&
      aws_cloudwatch_log_group.api_access.retention_in_days == 7
    )
    error_message = "Preserve request correlation, HTTP API metrics, and bounded lab settings."
  }
}

run "permission_drill_removes_grants_but_keeps_routes" {
  command = plan
  variables { enable_api_invoke_permission = false }
  assert {
    condition     = length(aws_lambda_permission.api_route) == 0 && length(aws_apigatewayv2_route.http) == 2
    error_message = "The integration drill must remove invocation grants, not HTTP routes."
  }
}

run "unsafe_timeout_is_rejected" {
  command = plan
  variables { function_timeout_seconds = 10 }
  expect_failures = [var.function_timeout_seconds]
}

run "excessive_lab_rate_is_rejected" {
  command = plan
  variables { throttle_rate_limit = 100 }
  expect_failures = [var.throttle_rate_limit]
}

run "non_dev_environment_is_rejected" {
  command = plan
  variables { environment = "prod" }
  expect_failures = [var.environment]
}
