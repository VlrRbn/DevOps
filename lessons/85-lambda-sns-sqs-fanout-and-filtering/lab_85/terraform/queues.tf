resource "aws_sqs_queue" "dead_letter" {
  for_each = local.consumers

  name                       = local.dead_letter_queue_names[each.key]
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true
}

resource "aws_sqs_queue" "source" {
  for_each = local.consumers

  name                       = local.source_queue_names[each.key]
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = var.queue_visibility_timeout_seconds
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter[each.key].arn
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

resource "aws_sqs_queue_redrive_allow_policy" "dead_letter" {
  for_each = local.consumers

  queue_url = aws_sqs_queue.dead_letter[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.source[each.key].arn]
  })
}

data "aws_iam_policy_document" "allow_topic" {
  for_each = local.consumers

  statement {
    sid       = "AllowOrdersTopicToSend"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.source[each.key].arn]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.orders.arn]
    }
  }

  # An SNS allow alone does not prevent a same-account IAM identity with
  # sqs:SendMessage from bypassing the topic and its filter policies.
  statement {
    sid       = "DenySendOutsideOrdersTopic"
    effect    = "Deny"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.source[each.key].arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnNotEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.orders.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.source[each.key].arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "allow_topic" {
  for_each = local.consumers

  queue_url = aws_sqs_queue.source[each.key].id
  policy    = data.aws_iam_policy_document.allow_topic[each.key].json
}
