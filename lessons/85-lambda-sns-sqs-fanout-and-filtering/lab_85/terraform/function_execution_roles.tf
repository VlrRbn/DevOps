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
  for_each = local.consumers

  name               = local.function_execution_role_names[each.key]
  assume_role_policy = data.aws_iam_policy_document.function_execution_trust.json
}

data "aws_iam_policy_document" "function_runtime_access" {
  for_each = local.consumers

  statement {
    sid    = "WriteOwnFunctionLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.function[each.key].arn}:*"]
  }

  statement {
    sid    = "ConsumeOwnSourceQueue"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.source[each.key].arn]
  }
}

resource "aws_iam_role_policy" "function_runtime_access" {
  for_each = local.consumers

  name   = local.function_runtime_policy_names[each.key]
  role   = aws_iam_role.function_execution[each.key].id
  policy = data.aws_iam_policy_document.function_runtime_access[each.key].json
}
