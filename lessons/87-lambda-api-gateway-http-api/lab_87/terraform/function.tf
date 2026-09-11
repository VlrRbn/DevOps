resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "http" {
  function_name = local.function_name
  description   = "Lesson 87 synchronous HTTP health and quote calculator"
  role          = aws_iam_role.function_execution.arn

  filename         = data.archive_file.function_package.output_path
  source_code_hash = data.archive_file.function_package.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.14"
  architectures    = ["arm64"]

  memory_size = 128
  timeout     = var.function_timeout_seconds

  depends_on = [aws_iam_role_policy.function_logs]
}
