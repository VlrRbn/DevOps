mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

override_resource {
  target          = aws_sqs_queue.dead_letter
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab84-dev-sqs-dlq.fifo"
  }
}

override_resource {
  target          = aws_sqs_queue.source
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab84-dev-sqs-work.fifo"
  }
}

run "source_and_dlq_are_fifo_queues" {
  command = plan

  assert {
    condition     = aws_sqs_queue.source.fifo_queue && endswith(aws_sqs_queue.source.name, ".fifo")
    error_message = "The source queue must be FIFO and its name must end with .fifo."
  }

  assert {
    condition     = aws_sqs_queue.dead_letter.fifo_queue && endswith(aws_sqs_queue.dead_letter.name, ".fifo")
    error_message = "A FIFO source queue must use a FIFO dead-letter queue."
  }
}

run "producer_must_supply_explicit_deduplication_ids" {
  command = plan

  assert {
    condition     = !aws_sqs_queue.source.content_based_deduplication
    error_message = "The lesson requires explicit MessageDeduplicationId values."
  }
}

run "mapping_preserves_partial_failure_and_fifo_limits" {
  command = plan

  assert {
    condition     = aws_lambda_event_source_mapping.source_queue.batch_size == 5
    error_message = "The FIFO lab must expose a multi-record batch."
  }

  assert {
    condition     = contains(aws_lambda_event_source_mapping.source_queue.function_response_types, "ReportBatchItemFailures")
    error_message = "The FIFO worker must report failed and unprocessed records."
  }

  assert {
    condition     = aws_lambda_event_source_mapping.source_queue.scaling_config[0].maximum_concurrency == 4
    error_message = "The FIFO source mapping must cap concurrent invocations at four."
  }
}

run "default_does_not_reserve_account_concurrency" {
  command = plan

  assert {
    condition     = aws_lambda_function.worker.reserved_concurrent_executions == null
    error_message = "The disposable lab must not reserve account concurrency by default."
  }
}

run "fifo_batch_size_above_ten_is_rejected" {
  command = plan

  variables {
    batch_size = 11
  }

  expect_failures = [var.batch_size]
}

run "reservation_below_mapping_limit_is_rejected" {
  command = plan

  variables {
    event_source_maximum_concurrency = 4
    function_reserved_concurrency    = 3
  }

  expect_failures = [aws_lambda_function.worker]
}

run "visibility_timeout_covers_lambda_retries" {
  command = plan

  assert {
    condition = (
      aws_sqs_queue.source.visibility_timeout_seconds >=
      6 * aws_lambda_function.worker.timeout
    )
    error_message = "Visibility timeout must be at least six times the Lambda timeout."
  }
}

run "unsafe_visibility_timeout_is_rejected" {
  command = plan

  variables {
    queue_visibility_timeout_seconds = 35
  }

  expect_failures = [aws_sqs_queue.source]
}

run "ordering_blockage_and_failure_signals_are_monitored" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.function_throttles.metric_name == "Throttles"
    error_message = "Lambda throttling must remain visible."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.source_oldest_message.metric_name == "ApproximateAgeOfOldestMessage"
    error_message = "Oldest-message age must expose a blocked FIFO group or backlog."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.dead_letter_visible.metric_name == "ApproximateNumberOfMessagesVisible"
    error_message = "FIFO DLQ depth must remain monitored."
  }
}
