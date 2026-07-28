# Lambda assumes this role only after an invocation has been authorized. Its
# permissions control the running handler, not who may invoke the function.
data "aws_iam_policy_document" "function_execution_trust" {
  statement {
    sid     = "AllowLambdaServiceToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "function_execution" {
  name               = local.function_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.function_execution_trust.json
}

# The handler writes only to its own log group. It does not need permission to
# invoke itself or another Lambda function.
data "aws_iam_policy_document" "function_log_access" {
  statement {
    sid    = "WriteFunctionLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.function.arn}:*"]
  }
}

resource "aws_iam_role_policy" "function_log_access" {
  name   = local.function_logs_policy_name
  role   = aws_iam_role.function_execution.id
  policy = data.aws_iam_policy_document.function_log_access.json
}
