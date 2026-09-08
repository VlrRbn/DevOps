# Все блоки создаются отдельно для audit и high_value через for_each.
# each.key связывает ресурсы одной ветки: её правило, source queue и обе DLQ.

# DLQ обработки: SQS переносит сюда сообщения из source queue после исчерпания
# попыток получения без успешной обработки. Lambda сама сюда не публикует.
# Хранение — 14 дней; long polling — 20 секунд; включено шифрование SQS.
resource "aws_sqs_queue" "processing_dead_letter" {
  for_each = local.consumers

  name                       = local.processing_dead_letter_queue_names[each.key]
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true
}

# DLQ доставки: EventBridge отправляет сюда события, которые не смог доставить
# в source queue. Назначается цели через dead_letter_config в eventbridge.tf.
# Это отдельная очередь: события в ней ещё не дошли до обработки Lambda.
resource "aws_sqs_queue" "delivery_dead_letter" {
  for_each = local.consumers

  name                       = local.delivery_dead_letter_queue_names[each.key]
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true
}

# Основной буфер ветки: EventBridge доставляет сюда, а Lambda event source mapping
# опрашивает очередь и вызывает обработчик. Хранение — 1 день.
# Visibility timeout скрывает полученное сообщение на время обработки.
resource "aws_sqs_queue" "source" {
  for_each = local.consumers

  name                       = local.source_queue_names[each.key]
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = var.queue_visibility_timeout_seconds
  sqs_managed_sse_enabled    = true

  # Куда SQS переносит сообщение после исчерпания maxReceiveCount.
  # Этот счётчик не связан с retry_policy доставки EventBridge.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dead_letter[each.key].arn
    maxReceiveCount     = var.max_receive_count
  })

  # Проверка учебного контракта: visibility timeout не меньше 6 тайм-аутов Lambda.
  lifecycle {
    precondition {
      condition = (
        var.queue_visibility_timeout_seconds >= 6 * var.function_timeout_seconds
      )
      error_message = "queue_visibility_timeout_seconds must be at least six times the Lambda timeout."
    }
  }
}

# Обратная сторона redrive: задаёт на processing DLQ, какая source queue
# вправе использовать её как DLQ. byQueue ограничивает перенос своей веткой.
# Это не разрешение EventBridge на SendMessage и не запуск повторной обработки.
resource "aws_sqs_queue_redrive_allow_policy" "processing_dead_letter" {
  for_each = local.consumers

  queue_url = aws_sqs_queue.processing_dead_letter[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.source[each.key].arn]
  })
}

# Собирает JSON resource policy исходной очереди; сам data-блок не назначает
# права в AWS. Ниже aws_sqs_queue_policy прикрепляет этот документ к очереди.
data "aws_iam_policy_document" "allow_eventbridge_source" {
  for_each = local.consumers

  statement {
    # Разрешает EventBridge доставку только от правила соответствующей ветки.
    # aws:SourceArn — ARN правила в контексте AWS-запроса, не поле source события.
    sid       = "AllowExpectedRuleToSend"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.source[each.key].arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.route[each.key].arn]
    }
  }

  # Явный Deny блокирует обход правила прямым SendMessage даже при IAM Allow.
  # При прямом вызове aws:SourceArn отсутствует; ArnNotEquals также охватывает это.
  statement {
    sid       = "DenySendOutsideExpectedRule"
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
      values   = [aws_cloudwatch_event_rule.route[each.key].arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.source[each.key].arn]

    # Запрещает операции с очередью при явно незащищённом транспорте.
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

# Назначает собранную resource policy исходной очереди каждой ветки.
resource "aws_sqs_queue_policy" "allow_eventbridge_source" {
  for_each = local.consumers

  queue_url = aws_sqs_queue.source[each.key].id
  policy    = data.aws_iam_policy_document.allow_eventbridge_source[each.key].json
}

# Собирает отдельную policy delivery DLQ. Право отправки в source queue
# не даёт EventBridge автоматического права сохранить событие в этой DLQ.
data "aws_iam_policy_document" "allow_eventbridge_delivery_dead_letter" {
  for_each = local.consumers

  statement {
    # Разрешает правилу сохранить событие при отказе доставки основной цели.
    sid       = "AllowExpectedRuleToSendFailedDelivery"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.delivery_dead_letter[each.key].arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.route[each.key].arn]
    }
  }

  statement {
    sid       = "DenySendOutsideExpectedRule"
    effect    = "Deny"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.delivery_dead_letter[each.key].arn]

    # Блокирует прямую публикацию и доставку от другого правила.
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnNotEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.route[each.key].arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.delivery_dead_letter[each.key].arn]

    # Запрещает операции с delivery DLQ без защищённого транспорта.
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

# Назначает delivery DLQ её собственную resource policy.
# Она должна оставаться рабочей при намеренном повреждении policy source queue.
resource "aws_sqs_queue_policy" "allow_eventbridge_delivery_dead_letter" {
  for_each = local.consumers

  queue_url = aws_sqs_queue.delivery_dead_letter[each.key].id
  policy    = data.aws_iam_policy_document.allow_eventbridge_delivery_dead_letter[each.key].json
}

# Собирает запрет незащищённого транспорта для processing DLQ.
# Здесь нет Allow для EventBridge: переносом управляет SQS через redrive.
# Право оператора читать DLQ задаётся отдельно, например его IAM policy.
data "aws_iam_policy_document" "processing_dead_letter_transport" {
  for_each = local.consumers

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.processing_dead_letter[each.key].arn]

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

# Назначает processing DLQ транспортную resource policy.
# Она дополняет redrive_allow_policy, а не заменяет её: у них разные задачи.
resource "aws_sqs_queue_policy" "processing_dead_letter_transport" {
  for_each = local.consumers

  queue_url = aws_sqs_queue.processing_dead_letter[each.key].id
  policy    = data.aws_iam_policy_document.processing_dead_letter_transport[each.key].json
}
