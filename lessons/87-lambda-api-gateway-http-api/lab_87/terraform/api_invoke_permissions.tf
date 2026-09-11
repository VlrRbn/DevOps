# Authorize only this API, stage, method and path to invoke the function.
# $default is the stage name in the ARN even though it is absent from the URL.
resource "aws_lambda_permission" "api_route" {
  for_each = var.enable_api_invoke_permission ? local.routes : {}

  statement_id   = "AllowApiGateway-${each.key}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.http.function_name
  principal      = "apigateway.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = "${aws_apigatewayv2_api.http.execution_arn}/${local.stage_name}/${each.value.method}/${each.value.path}"
}
