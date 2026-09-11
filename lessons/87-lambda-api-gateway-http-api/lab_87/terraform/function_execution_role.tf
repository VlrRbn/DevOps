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

# These are permissions used by the function. They do not authorize callers
# of either the HTTP API or Lambda's Invoke API.
resource "aws_iam_role_policy" "function_logs" {
  name = local.function_log_policy_name
  role = aws_iam_role.function_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteOwnFunctionLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.function.arn}:*"
    }]
  })
}
