locals {
  resource_prefix = "${var.project_name}-${var.environment}"

  function_name                = "${local.resource_prefix}-lambda-fifo-worker"
  function_execution_role_name = "${local.resource_prefix}-role-lambda-fifo-worker"
  function_runtime_policy_name = "${local.resource_prefix}-policy-for-role-lambda-fifo-worker"
  source_queue_name            = "${local.resource_prefix}-sqs-work.fifo"
  dead_letter_queue_name       = "${local.resource_prefix}-sqs-dlq.fifo"

  function_throttles_alarm_name = "${local.resource_prefix}-alarm-lambda-throttles"
  source_age_alarm_name         = "${local.resource_prefix}-alarm-sqs-oldest-message"
  dlq_depth_alarm_name          = "${local.resource_prefix}-alarm-sqs-dlq-visible"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Lesson      = "84"
  }
}
