# FIFO ordering is enforced per MessageGroupId. Different groups may run in
# parallel, bounded by this source-level maximum concurrency.
resource "aws_lambda_event_source_mapping" "source_queue" {
  event_source_arn = aws_sqs_queue.source.arn
  function_name    = aws_lambda_function.worker.arn
  enabled          = true

  batch_size              = var.batch_size
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = var.event_source_maximum_concurrency
  }

  depends_on = [aws_iam_role_policy.function_runtime_access]
}
