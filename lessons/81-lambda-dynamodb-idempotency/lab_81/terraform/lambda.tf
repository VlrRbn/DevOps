resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "idempotent_worker" {
  function_name = local.function_name
  description   = "Lesson 81 Lambda worker protected by a DynamoDB idempotency record"
  role          = aws_iam_role.function_execution.arn

  filename         = data.archive_file.function_package.output_path
  source_code_hash = data.archive_file.function_package.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.14"
  architectures    = ["arm64"]

  memory_size = 128
  timeout     = 10

  environment {
    variables = {
      APP_ENV                = var.environment
      IDEMPOTENCY_TABLE_NAME = aws_dynamodb_table.idempotency.name
      CLAIM_TTL_SECONDS      = tostring(var.claim_ttl_seconds)
      RECORD_TTL_SECONDS     = tostring(var.record_ttl_seconds)
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.function,
    aws_iam_role_policy.function_runtime_access,
  ]
}
