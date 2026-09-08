mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

override_resource {
  target          = aws_cloudwatch_event_bus.orders
  override_during = plan
  values = {
    arn  = "arn:aws:events:eu-west-1:123456789012:event-bus/lab86-dev-orders-bus"
    name = "lab86-dev-orders-bus"
  }
}

override_resource {
  target          = aws_cloudwatch_event_rule.route["audit"]
  override_during = plan
  values = {
    arn  = "arn:aws:events:eu-west-1:123456789012:rule/lab86-dev-orders-bus/lab86-dev-audit-route"
    name = "lab86-dev-audit-route"
  }
}

override_resource {
  target          = aws_cloudwatch_event_rule.route["high_value"]
  override_during = plan
  values = {
    arn  = "arn:aws:events:eu-west-1:123456789012:rule/lab86-dev-orders-bus/lab86-dev-high-value-route"
    name = "lab86-dev-high-value-route"
  }
}

override_resource {
  target          = aws_sqs_queue.source["audit"]
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab86-dev-audit-events"
  }
}

override_resource {
  target          = aws_sqs_queue.source["high_value"]
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab86-dev-high-value-events"
  }
}

override_resource {
  target          = aws_sqs_queue.processing_dead_letter["audit"]
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab86-dev-audit-events-processing-dlq"
  }
}

override_resource {
  target          = aws_sqs_queue.processing_dead_letter["high_value"]
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab86-dev-high-value-events-processing-dlq"
  }
}

override_resource {
  target          = aws_sqs_queue.delivery_dead_letter["audit"]
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab86-dev-audit-events-delivery-dlq"
  }
}

override_resource {
  target          = aws_sqs_queue.delivery_dead_letter["high_value"]
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab86-dev-high-value-events-delivery-dlq"
  }
}

run "custom_bus_and_two_rules_define_the_routing_plane" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_bus.orders.name == "lab86-dev-orders-bus"
    error_message = "The lab must use its own custom event bus."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.route) == 2
    error_message = "Audit and high-value routing must use separate rules."
  }
}

run "audit_pattern_accepts_both_order_event_types" {
  command = plan

  assert {
    condition = (
      contains(jsondecode(aws_cloudwatch_event_rule.route["audit"].event_pattern).source, "com.devops.orders") &&
      contains(jsondecode(aws_cloudwatch_event_rule.route["audit"].event_pattern)["detail-type"], "Order Created") &&
      contains(jsondecode(aws_cloudwatch_event_rule.route["audit"].event_pattern)["detail-type"], "Order Refunded")
    )
    error_message = "Audit must accept created and refunded events from the expected source."
  }
}

run "high_value_pattern_uses_numeric_content_filtering" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_cloudwatch_event_rule.route["high_value"].event_pattern)["detail-type"] == ["Order Created"] &&
      jsondecode(aws_cloudwatch_event_rule.route["high_value"].event_pattern).detail.amount[0].numeric == [">=", 100]
    )
    error_message = "High-value routing must accept created orders with amount >= 100."
  }
}

run "each_rule_targets_only_its_source_queue" {
  command = plan

  assert {
    condition = alltrue([
      for consumer in local.consumers :
      aws_cloudwatch_event_target.source_queue[consumer].arn == aws_sqs_queue.source[consumer].arn
    ])
    error_message = "Each EventBridge rule must target its corresponding source queue."
  }
}

run "each_target_has_retry_and_delivery_dead_letter_controls" {
  command = plan

  assert {
    condition = alltrue([
      for consumer in local.consumers :
      aws_cloudwatch_event_target.source_queue[consumer].dead_letter_config[0].arn == aws_sqs_queue.delivery_dead_letter[consumer].arn
    ])
    error_message = "Each EventBridge target must use its own delivery DLQ."
  }

  assert {
    condition = alltrue([
      for target in aws_cloudwatch_event_target.source_queue :
      target.retry_policy[0].maximum_retry_attempts == 10 &&
      target.retry_policy[0].maximum_event_age_in_seconds == 3600
    ])
    error_message = "Each target must define the lesson retry boundary explicitly."
  }
}

run "source_queues_redrive_only_to_processing_dead_letter_queues" {
  command = plan

  assert {
    condition = alltrue([
      for consumer in local.consumers :
      jsondecode(aws_sqs_queue.source[consumer].redrive_policy).deadLetterTargetArn == aws_sqs_queue.processing_dead_letter[consumer].arn
    ])
    error_message = "SQS processing failures must not use the EventBridge delivery DLQ."
  }
}

run "each_lambda_consumes_only_its_branch" {
  command = plan

  assert {
    condition = alltrue([
      for consumer in local.consumers :
      aws_lambda_event_source_mapping.source_queue[consumer].event_source_arn == aws_sqs_queue.source[consumer].arn
    ])
    error_message = "Each Lambda mapping must use its corresponding source queue."
  }

  assert {
    condition = alltrue([
      for consumer in local.consumers :
      aws_lambda_function.consumer[consumer].environment[0].variables.CONSUMER_NAME == consumer
    ])
    error_message = "Each function must know which routing branch it represents."
  }
}

run "partial_batch_and_branch_concurrency_are_enabled" {
  command = plan

  assert {
    condition = alltrue([
      for mapping in aws_lambda_event_source_mapping.source_queue :
      contains(mapping.function_response_types, "ReportBatchItemFailures")
    ])
    error_message = "Both standard SQS consumers must report individual record failures."
  }

  assert {
    condition = alltrue([
      for mapping in aws_lambda_event_source_mapping.source_queue :
      mapping.scaling_config[0].maximum_concurrency == 2
    ])
    error_message = "Each branch must have an explicit concurrency cap of two."
  }
}

run "unsafe_visibility_timeout_is_rejected" {
  command = plan

  variables {
    queue_visibility_timeout_seconds = 35
  }

  expect_failures = [
    aws_sqs_queue.source["audit"],
    aws_sqs_queue.source["high_value"],
  ]
}

run "invalid_high_value_threshold_is_rejected" {
  command = plan

  variables {
    high_value_threshold = 0
  }

  expect_failures = [var.high_value_threshold]
}

run "invalid_target_retry_count_is_rejected" {
  command = plan

  variables {
    target_maximum_retry_attempts = 186
  }

  expect_failures = [var.target_maximum_retry_attempts]
}

run "delivery_and_processing_failure_signals_are_separate" {
  command = plan

  assert {
    condition = (
      length(aws_cloudwatch_metric_alarm.processing_dead_letter_visible) == 2 &&
      length(aws_cloudwatch_metric_alarm.delivery_dead_letter_visible) == 2 &&
      length(aws_cloudwatch_metric_alarm.eventbridge_failed_invocations) == 2
    )
    error_message = "Each branch must expose separate delivery and processing failure signals."
  }
}
