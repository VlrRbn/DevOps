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
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab83-dev-sqs-dlq"
  }
}

override_resource {
  target          = aws_sqs_queue.source
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab83-dev-sqs-work"
  }
}

run "event_source_mapping_has_bounded_concurrency" {
  command = plan

  assert {
    condition     = aws_lambda_event_source_mapping.source_queue.scaling_config[0].maximum_concurrency == 2
    error_message = "The default SQS event source mapping must cap concurrency at two."
  }

  assert {
    condition     = aws_lambda_event_source_mapping.source_queue.batch_size == 1
    error_message = "The lab must use one message per invocation so concurrency remains observable."
  }

  assert {
    condition     = contains(aws_lambda_event_source_mapping.source_queue.function_response_types, "ReportBatchItemFailures")
    error_message = "Per-record failures must remain enabled while scaling is tested."
  }
}

run "default_does_not_reserve_account_concurrency" {
  command = plan

  assert {
    condition     = aws_lambda_function.worker.reserved_concurrent_executions == null
    error_message = "The disposable lab must not reserve scarce account concurrency by default."
  }
}

run "matching_reserved_concurrency_is_allowed" {
  command = plan

  variables {
    function_reserved_concurrency = 2
  }

  assert {
    condition     = aws_lambda_function.worker.reserved_concurrent_executions == 2
    error_message = "A reservation equal to the mapping cap must be accepted."
  }
}

run "mapping_limit_below_two_is_rejected" {
  command = plan

  variables {
    event_source_maximum_concurrency = 1
  }

  expect_failures = [var.event_source_maximum_concurrency]
}

run "reservation_below_mapping_limit_is_rejected" {
  command = plan

  variables {
    event_source_maximum_concurrency = 3
    function_reserved_concurrency    = 2
  }

  expect_failures = [aws_lambda_function.worker]
}

run "visibility_timeout_covers_throttling_retries" {
  command = plan

  assert {
    condition = aws_sqs_queue.source.visibility_timeout_seconds >= (
      6 * aws_lambda_function.worker.timeout +
      aws_lambda_event_source_mapping.source_queue.maximum_batching_window_in_seconds
    )
    error_message = "Visibility timeout must cover processing and throttling retries."
  }
}

run "unsafe_visibility_timeout_is_rejected" {
  command = plan

  variables {
    queue_visibility_timeout_seconds = 89
  }

  expect_failures = [aws_sqs_queue.source]
}

run "backpressure_and_failure_signals_are_monitored" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.function_throttles.metric_name == "Throttles"
    error_message = "Lambda throttling must be monitored."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.source_oldest_message.metric_name == "ApproximateAgeOfOldestMessage"
    error_message = "Oldest-message age must represent queue lag."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.dead_letter_visible.metric_name == "ApproximateNumberOfMessagesVisible"
    error_message = "DLQ depth must remain monitored."
  }
}
