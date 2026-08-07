# Lambda polls SQS and invokes the function with a batch. ReportBatchItemFailures
# lets the handler acknowledge successful records while retrying only failures.
resource "aws_lambda_event_source_mapping" "source_queue" {
  event_source_arn = aws_sqs_queue.source.arn
  function_name    = aws_lambda_function.sqs_consumer.arn
  enabled          = true

  batch_size                         = var.batch_size
  maximum_batching_window_in_seconds = var.maximum_batching_window_seconds
  function_response_types            = ["ReportBatchItemFailures"]

  depends_on = [aws_iam_role_policy.function_runtime_access]
}
