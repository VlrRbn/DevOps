# lambda_caller_identity_policy mode puts InvokeFunction permission on the
# Lambda caller role and scopes it to exactly one unqualified function ARN.
data "aws_iam_policy_document" "lambda_caller_invoke_access" {
  count = var.invoke_permission_mode == "lambda_caller_identity_policy" ? 1 : 0

  statement {
    sid       = "InvokeOnlyLessonFunction"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.greeting.arn]
  }
}

resource "aws_iam_role_policy" "lambda_caller_invoke_access" {
  count = var.invoke_permission_mode == "lambda_caller_identity_policy" ? 1 : 0

  name   = local.caller_invoke_policy_name
  role   = aws_iam_role.lambda_caller.id
  policy = data.aws_iam_policy_document.lambda_caller_invoke_access[0].json
}

# function_resource_policy mode puts the Allow on the function instead. The
# Lambda caller role has no identity-based InvokeFunction policy in this mode.
resource "aws_lambda_permission" "function_allows_lambda_caller" {
  count = var.invoke_permission_mode == "function_resource_policy" ? 1 : 0

  statement_id  = "AllowLambdaCallerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.greeting.function_name
  principal     = aws_iam_role.lambda_caller.arn
}
