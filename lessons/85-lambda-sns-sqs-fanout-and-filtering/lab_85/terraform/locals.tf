locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  consumers       = toset(["audit", "billing"])

  topic_name = "${local.resource_prefix}-orders-events"

  function_names = {
    for consumer in local.consumers :
    consumer => "${local.resource_prefix}-${consumer}-consumer"
  }

  function_execution_role_names = {
    for consumer in local.consumers :
    consumer => "${local.function_names[consumer]}-execution-role"
  }

  function_runtime_policy_names = {
    for consumer in local.consumers :
    consumer => "${local.function_execution_role_names[consumer]}-runtime-policy"
  }

  source_queue_names = {
    for consumer in local.consumers :
    consumer => "${local.resource_prefix}-${consumer}-events"
  }

  dead_letter_queue_names = {
    for consumer in local.consumers :
    consumer => "${local.resource_prefix}-${consumer}-events-dlq"
  }
}
