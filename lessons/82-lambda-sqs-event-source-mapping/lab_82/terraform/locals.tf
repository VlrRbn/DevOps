locals {
  resource_prefix = "${var.project_name}-${var.environment}"

  function_name                = "${local.resource_prefix}-lambda-sqs-consumer"
  function_execution_role_name = "${local.resource_prefix}-role-lambda-sqs-consumer"
  function_runtime_policy_name = "${local.resource_prefix}-policy-for-role-lambda-sqs-consumer"
  source_queue_name            = "${local.resource_prefix}-sqs-source"
  dead_letter_queue_name       = "${local.resource_prefix}-sqs-dlq"

  function_errors_alarm_name = "${local.resource_prefix}-alarm-lambda-errors"
  source_age_alarm_name      = "${local.resource_prefix}-alarm-sqs-oldest-message"
  dlq_depth_alarm_name       = "${local.resource_prefix}-alarm-sqs-dlq-visible"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Lesson      = "82"
  }
}
