mock_provider "aws" {
  # aws_iam_policy_document is local in a real plan, but a mocked provider must
  # still return syntactically valid JSON for IAM resource validation.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

override_resource {
  target          = aws_sqs_queue.lambda_failure_destination
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab80-dev-lambda-failures"
  }
}

run "async_failure_path_is_bounded" {
  command = plan

  assert {
    condition     = aws_lambda_function_event_invoke_config.async_worker.maximum_retry_attempts == 1
    error_message = "The lab must use one retry after the initial failed attempt."
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.async_worker.maximum_event_age_in_seconds == 300
    error_message = "The lab must expire asynchronous events after 300 seconds."
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.async_worker.destination_config[0].on_failure[0].destination == aws_sqs_queue.lambda_failure_destination.arn
    error_message = "Failed asynchronous invocations must be routed to the SQS failure destination."
  }
}

run "failure_queue_has_safe_defaults" {
  command = plan

  assert {
    condition     = aws_sqs_queue.lambda_failure_destination.sqs_managed_sse_enabled
    error_message = "The failure queue must use SQS-managed encryption."
  }

  assert {
    condition     = aws_sqs_queue.lambda_failure_destination.message_retention_seconds == 86400
    error_message = "The temporary lab queue must retain messages for one day."
  }
}

run "async_failure_path_is_observable" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.function.retention_in_days == 7
    error_message = "Function logs must have bounded retention."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.function_errors.metric_name == "Errors"
    error_message = "Handler failures must be monitored through the Lambda Errors metric."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.destination_delivery_failures.metric_name == "DestinationDeliveryFailures"
    error_message = "Failure destination delivery must have its own alarm."
  }
}

run "retry_override_is_respected" {
  command = plan

  variables {
    maximum_retry_attempts = 0
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.async_worker.maximum_retry_attempts == 0
    error_message = "A zero-retry override must be preserved by the module root."
  }
}
