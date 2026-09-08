locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  consumers       = toset(["audit", "high_value"])

  event_bus_name = "${local.resource_prefix}-orders-bus"

  function_names = {
    for consumer in local.consumers :
    consumer => "${local.resource_prefix}-${replace(consumer, "_", "-")}-consumer"
  }

  function_execution_role_names = {
    for consumer in local.consumers :
    consumer => "${local.function_names[consumer]}-execution-role"
  }

  function_runtime_policy_names = {
    for consumer in local.consumers :
    consumer => "${local.function_execution_role_names[consumer]}-runtime-policy"
  }

  rule_names = {
    for consumer in local.consumers :
    consumer => "${local.resource_prefix}-${replace(consumer, "_", "-")}-route"
  }

  source_queue_names = {
    for consumer in local.consumers :
    consumer => "${local.resource_prefix}-${replace(consumer, "_", "-")}-events"
  }

  processing_dead_letter_queue_names = {
    for consumer in local.consumers :
    consumer => "${local.source_queue_names[consumer]}-processing-dlq"
  }

  delivery_dead_letter_queue_names = {
    for consumer in local.consumers :
    consumer => "${local.source_queue_names[consumer]}-delivery-dlq"
  }

  event_patterns = {
    audit = jsonencode({
      source      = [var.event_source]
      detail-type = ["Order Created", "Order Refunded"]
    })
    high_value = jsonencode({
      source      = [var.event_source]
      detail-type = ["Order Created"]
      detail = {
        amount = [{ numeric = [">=", var.high_value_threshold] }]
      }
    })
  }
}
