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
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab82-dev-sqs-dlq"
  }
}

override_resource {
  target          = aws_sqs_queue.source
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab82-dev-sqs-source"
  }
}

run "queues_have_bounded_redrive_contract" {
  command = plan

  assert {
    condition     = aws_sqs_queue.source.sqs_managed_sse_enabled
    error_message = "The source queue must use SQS-managed encryption."
  }

  assert {
    condition     = aws_sqs_queue.dead_letter.sqs_managed_sse_enabled
    error_message = "The DLQ must use SQS-managed encryption."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.source.redrive_policy).deadLetterTargetArn == aws_sqs_queue.dead_letter.arn
    error_message = "The source queue must redrive to the Terraform-managed DLQ."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.source.redrive_policy).maxReceiveCount == 3
    error_message = "The default poison-message budget must be three receives."
  }
}

run "visibility_timeout_covers_lambda_processing" {
  command = plan

  assert {
    condition = aws_sqs_queue.source.visibility_timeout_seconds >= (
      6 * aws_lambda_function.sqs_consumer.timeout +
      aws_lambda_event_source_mapping.source_queue.maximum_batching_window_in_seconds
    )
    error_message = "Visibility timeout must cover Lambda retries and the batching window."
  }
}

run "event_source_mapping_uses_partial_batch_failures" {
  command = plan

  assert {
    condition     = aws_lambda_event_source_mapping.source_queue.event_source_arn == aws_sqs_queue.source.arn
    error_message = "The event source mapping must poll the exact source queue."
  }

  assert {
    condition     = contains(aws_lambda_event_source_mapping.source_queue.function_response_types, "ReportBatchItemFailures")
    error_message = "Partial batch failure reporting must be enabled."
  }

  assert {
    condition     = aws_lambda_event_source_mapping.source_queue.batch_size == 5
    error_message = "The default lab batch size must be five records."
  }
}

run "observability_covers_function_lag_and_dlq" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.function_errors.metric_name == "Errors"
    error_message = "Whole-invocation Lambda failures must be monitored."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.source_oldest_message.metric_name == "ApproximateAgeOfOldestMessage"
    error_message = "Source queue lag must be monitored."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.dead_letter_visible.metric_name == "ApproximateNumberOfMessagesVisible"
    error_message = "Visible DLQ messages must be monitored."
  }
}

run "valid_batch_and_redrive_overrides_are_preserved" {
  command = plan

  variables {
    batch_size        = 2
    max_receive_count = 4
  }

  assert {
    condition     = aws_lambda_event_source_mapping.source_queue.batch_size == 2
    error_message = "A valid batch size override must reach the event source mapping."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.source.redrive_policy).maxReceiveCount == 4
    error_message = "A valid receive-count override must reach the redrive policy."
  }
}
