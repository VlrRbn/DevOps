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

# Runtime permissions are limited to the function's log group and the exact
# SQS queue configured as its asynchronous failure destination.
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
    sid       = "SendFailureRecordToDestination"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.lambda_failure_destination.arn]
  }
}

resource "aws_iam_role_policy" "function_runtime_access" {
  name   = local.function_runtime_policy_name
  role   = aws_iam_role.function_execution.id
  policy = data.aws_iam_policy_document.function_runtime_access.json
}
