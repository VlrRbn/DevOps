# Lambda assumes this role while processing a batch. Invocation is controlled
# by the event source mapping, not by granting a human principal lambda:InvokeFunction.
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

# The poller uses the function execution role for data-plane access to the exact
# source queue. It may not receive from or delete messages in the DLQ.
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
    sid    = "ConsumeSourceQueue"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.source.arn]
  }
}

resource "aws_iam_role" "function_execution" {
  name               = local.function_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.function_execution_trust.json
}

resource "aws_iam_role_policy" "function_runtime_access" {
  name   = local.function_runtime_policy_name
  role   = aws_iam_role.function_execution.id
  policy = data.aws_iam_policy_document.function_runtime_access.json
}
