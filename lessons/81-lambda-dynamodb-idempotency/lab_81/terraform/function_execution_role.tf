# Lambda assumes this role at runtime. It does not grant invocation access.
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

# The handler needs only logs and item-level operations on one exact table.
# Scan, Query, DeleteItem, table administration, and wildcard resources are not
# part of the runtime contract.
data "aws_iam_policy_document" "function_runtime_access" {
  statement {
    sid    = "WriteFunctionLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.function.arn}:*"]
  }

  statement {
    sid    = "UseIdempotencyRecords"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.idempotency.arn]
  }
}

resource "aws_iam_role_policy" "function_runtime_access" {
  name   = local.function_runtime_policy_name
  role   = aws_iam_role.function_execution.id
  policy = data.aws_iam_policy_document.function_runtime_access.json
}
