resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "async_worker" {
  function_name = local.function_name
  description   = "Lesson 80 asynchronous invocation and failure destination worker"
  role          = aws_iam_role.function_execution.arn

  filename         = data.archive_file.function_package.output_path
  source_code_hash = data.archive_file.function_package.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.14"
  architectures    = ["arm64"]

  memory_size = 128
  timeout     = 5

  environment {
    variables = {
      APP_ENV = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.function,
    aws_iam_role_policy.function_runtime_access,
  ]
}
