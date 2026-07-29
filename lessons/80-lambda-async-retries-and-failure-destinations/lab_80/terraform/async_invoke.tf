# These controls apply only to asynchronous invocation. A synchronous
# RequestResponse call returns the handler error directly and does not use
# Lambda's managed asynchronous retry queue or destinations.
resource "aws_lambda_function_event_invoke_config" "async_worker" {
  function_name                = aws_lambda_function.async_worker.function_name
  maximum_event_age_in_seconds = var.maximum_event_age_in_seconds
  maximum_retry_attempts       = var.maximum_retry_attempts

  destination_config {
    on_failure {
      destination = aws_sqs_queue.lambda_failure_destination.arn
    }
  }

  depends_on = [aws_iam_role_policy.function_runtime_access]
}
