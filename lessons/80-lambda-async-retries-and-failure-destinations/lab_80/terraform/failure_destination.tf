resource "aws_sqs_queue" "lambda_failure_destination" {
  name                       = local.failure_queue_name
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true
}
