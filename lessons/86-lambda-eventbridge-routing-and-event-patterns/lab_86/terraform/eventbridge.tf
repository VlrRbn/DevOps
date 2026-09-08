resource "aws_cloudwatch_event_bus" "orders" {
  name = local.event_bus_name
}

resource "aws_cloudwatch_event_rule" "route" {
  for_each = local.event_patterns

  name           = local.rule_names[each.key]
  description    = "Lesson 86 routing rule for the ${each.key} branch"
  event_bus_name = aws_cloudwatch_event_bus.orders.name
  event_pattern  = each.value
}

resource "aws_cloudwatch_event_target" "source_queue" {
  for_each = local.consumers

  event_bus_name = aws_cloudwatch_event_bus.orders.name
  rule           = aws_cloudwatch_event_rule.route[each.key].name
  target_id      = "${replace(each.key, "_", "-")}-source-queue"
  arn            = aws_sqs_queue.source[each.key].arn

  retry_policy {
    maximum_event_age_in_seconds = var.target_maximum_event_age_seconds
    maximum_retry_attempts       = var.target_maximum_retry_attempts
  }

  dead_letter_config {
    arn = aws_sqs_queue.delivery_dead_letter[each.key].arn
  }

  depends_on = [
    aws_sqs_queue_policy.allow_eventbridge_source,
    aws_sqs_queue_policy.allow_eventbridge_delivery_dead_letter,
  ]
}
