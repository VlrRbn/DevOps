mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

override_resource {
  target          = aws_sns_topic.orders
  override_during = plan
  values = {
    arn  = "arn:aws:sns:eu-west-1:123456789012:lab85-dev-orders-events"
    name = "lab85-dev-orders-events"
  }
}

override_resource {
  target          = aws_sqs_queue.source["audit"]
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab85-dev-audit-events"
  }
}

override_resource {
  target          = aws_sqs_queue.source["billing"]
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab85-dev-billing-events"
  }
}

override_resource {
  target          = aws_sqs_queue.dead_letter["audit"]
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab85-dev-audit-events-dlq"
  }
}

override_resource {
  target          = aws_sqs_queue.dead_letter["billing"]
  override_during = plan
  values = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:lab85-dev-billing-events-dlq"
  }
}

run "topic_and_subscriptions_form_two_raw_branches" {
  command = plan

  assert {
    condition     = aws_sns_topic.orders.kms_master_key_id == "alias/aws/sns"
    error_message = "The shared topic must use SNS server-side encryption."
  }

  assert {
    condition     = aws_sns_topic_subscription.audit.raw_message_delivery
    error_message = "The audit branch must receive the original published body."
  }

  assert {
    condition     = aws_sns_topic_subscription.billing.raw_message_delivery
    error_message = "The billing branch must receive the original published body."
  }
}

run "billing_subscription_filters_message_attributes" {
  command = plan

  assert {
    condition     = aws_sns_topic_subscription.billing.filter_policy_scope == "MessageAttributes"
    error_message = "Billing routing must use SNS message attributes."
  }

  assert {
    condition = (
      contains(jsondecode(aws_sns_topic_subscription.billing.filter_policy).event_type, "order.created") &&
      contains(jsondecode(aws_sns_topic_subscription.billing.filter_policy).event_type, "order.refunded")
    )
    error_message = "Billing must accept the two order event types used by the lesson."
  }
}

run "each_branch_has_its_own_source_queue_and_dlq" {
  command = plan

  assert {
    condition     = length(aws_sqs_queue.source) == 2 && length(aws_sqs_queue.dead_letter) == 2
    error_message = "Audit and billing must have independent source queues and DLQs."
  }

  assert {
    condition = alltrue([
      for consumer in local.consumers :
      jsondecode(aws_sqs_queue.source[consumer].redrive_policy).deadLetterTargetArn == aws_sqs_queue.dead_letter[consumer].arn
    ])
    error_message = "Each source queue must redrive only to its own DLQ."
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
    error_message = "Each function must know which fan-out branch it represents."
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
    aws_sqs_queue.source["billing"],
  ]
}

run "empty_billing_filter_is_rejected" {
  command = plan

  variables {
    billing_event_types = []
  }

  expect_failures = [var.billing_event_types]
}

run "branch_backlogs_and_delivery_failures_are_monitored" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.source_oldest_message) == 2
    error_message = "Each branch must monitor oldest-message age."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.dead_letter_visible) == 2
    error_message = "Each branch must monitor its own DLQ."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.sns_delivery_failures.metric_name == "NumberOfNotificationsFailed"
    error_message = "SNS delivery failures must be monitored."
  }
}
