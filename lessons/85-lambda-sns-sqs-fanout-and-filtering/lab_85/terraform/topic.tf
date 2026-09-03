resource "aws_sns_topic" "orders" {
  name              = local.topic_name
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "audit" {
  topic_arn            = aws_sns_topic.orders.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.source["audit"].arn
  raw_message_delivery = true

  depends_on = [aws_sqs_queue_policy.allow_topic]
}

resource "aws_sns_topic_subscription" "billing" {
  topic_arn            = aws_sns_topic.orders.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.source["billing"].arn
  raw_message_delivery = true

  filter_policy_scope = "MessageAttributes"
  filter_policy = jsonencode({
    event_type = var.billing_event_types
  })

  depends_on = [aws_sqs_queue_policy.allow_topic]
}
