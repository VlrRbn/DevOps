resource "aws_cloudwatch_log_group" "function" {
  for_each = local.consumers

  name              = "/aws/lambda/${local.function_names[each.key]}"
  retention_in_days = 7
}

resource "aws_lambda_function" "consumer" {
  for_each = local.consumers

  function_name = local.function_names[each.key]
  description   = "Lesson 85 ${each.key} consumer for SNS-to-SQS fan-out"
  role          = aws_iam_role.function_execution[each.key].arn

  filename         = data.archive_file.function_package.output_path
  source_code_hash = data.archive_file.function_package.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.14"
  architectures    = ["arm64"]

  memory_size = 128
  timeout     = var.function_timeout_seconds

  environment {
    variables = {
      CONSUMER_NAME = each.key
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.function,
    aws_iam_role_policy.function_runtime_access,
  ]
}
