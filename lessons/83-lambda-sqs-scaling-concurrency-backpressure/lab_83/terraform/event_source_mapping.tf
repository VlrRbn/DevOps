# This cap applies only to this source mapping. It protects downstream capacity
# without reserving regional Lambda concurrency for an otherwise idle lab.
resource "aws_lambda_event_source_mapping" "source_queue" {
  event_source_arn = aws_sqs_queue.source.arn
  function_name    = aws_lambda_function.worker.arn
  enabled          = true

  batch_size                         = var.batch_size
  maximum_batching_window_in_seconds = var.maximum_batching_window_seconds
  function_response_types            = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = var.event_source_maximum_concurrency
  }

  depends_on = [aws_iam_role_policy.function_runtime_access]
}
