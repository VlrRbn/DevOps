resource "aws_lambda_event_source_mapping" "source_queue" {
  for_each = local.consumers

  event_source_arn = aws_sqs_queue.source[each.key].arn
  function_name    = aws_lambda_function.consumer[each.key].arn
  enabled          = true

  batch_size              = var.batch_size
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = var.event_source_maximum_concurrency
  }

  depends_on = [aws_iam_role_policy.function_runtime_access]
}
