locals {
  function_name = "${var.project_name}-${var.environment}-hello"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Lesson      = "78"
  }
}

data "archive_file" "function" {
  type             = "zip"
  source_file      = "${path.module}/../app/lambda_function.py"
  output_file_mode = "0644"
  output_path      = "${path.module}/.terraform/lambda_function.zip"
}

data "aws_iam_policy_document" "lambda_trust" {
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

resource "aws_iam_role" "lambda" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 7
}

data "aws_iam_policy_document" "logs" {
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

resource "aws_iam_role_policy" "logs" {
  name   = "${local.function_name}-logs"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.logs.json
}

resource "aws_lambda_function" "hello" {
  function_name = local.function_name
  description   = "Lesson 78 Lambda fundamentals function"
  role          = aws_iam_role.lambda.arn

  filename         = data.archive_file.function.output_path
  source_code_hash = data.archive_file.function.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.14"
  architectures    = ["arm64"]

  memory_size                    = 128
  timeout                        = 5
  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = {
      APP_ENV = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.function,
    aws_iam_role_policy.logs,
  ]
}
