# Package the single-file handler into the ZIP archive expected by Lambda.
data "archive_file" "function" {
  type             = "zip"
  source_file      = "${path.module}/../app/lambda_function.py"
  output_file_mode = "0644"
  output_path      = "${path.module}/.terraform/lambda_function.zip"
}

# Create the log group explicitly so retention and IAM scope are managed before
# the first invocation instead of relying on Lambda's implicit creation.
resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "greeting" {
  function_name = local.function_name
  description   = "Lesson 79 Lambda IAM and invocation permissions function"
  role          = aws_iam_role.function_execution.arn

  filename         = data.archive_file.function.output_path
  source_code_hash = data.archive_file.function.output_base64sha256
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
    aws_iam_role_policy.function_log_access,
  ]
}
