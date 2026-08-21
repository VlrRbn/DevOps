resource "aws_sqs_queue" "dead_letter" {
  name                        = local.dead_letter_queue_name
  fifo_queue                  = true
  content_based_deduplication = false
  message_retention_seconds   = 1209600
  receive_wait_time_seconds   = 20
  visibility_timeout_seconds  = 30
  sqs_managed_sse_enabled     = true
}

resource "aws_sqs_queue" "source" {
  name                        = local.source_queue_name
  fifo_queue                  = true
  content_based_deduplication = false
  message_retention_seconds   = 86400
  receive_wait_time_seconds   = 20
  visibility_timeout_seconds  = var.queue_visibility_timeout_seconds
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter.arn
    maxReceiveCount     = var.max_receive_count
  })

  lifecycle {
    precondition {
      condition = (
        var.queue_visibility_timeout_seconds >= 6 * var.function_timeout_seconds
      )
      error_message = "queue_visibility_timeout_seconds must be at least six times the Lambda timeout."
    }
  }
}

# Only this FIFO source queue may move exhausted messages into the FIFO DLQ.
resource "aws_sqs_queue_redrive_allow_policy" "dead_letter" {
  queue_url = aws_sqs_queue.dead_letter.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.source.arn]
  })
}
