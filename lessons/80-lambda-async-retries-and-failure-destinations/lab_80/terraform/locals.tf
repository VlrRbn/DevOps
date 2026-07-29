locals {
  resource_prefix = "${var.project_name}-${var.environment}"

  function_name                = "${local.resource_prefix}-lambda-async-worker"
  function_execution_role_name = "${local.resource_prefix}-role-lambda-execution"
  function_runtime_policy_name = "${local.resource_prefix}-policy-for-role-lambda-execution-allow-logs-and-failure-delivery"
  failure_queue_name           = "${local.resource_prefix}-sqs-lambda-failure-destination"

  function_errors_alarm_name               = "${local.resource_prefix}-alarm-lambda-errors"
  destination_delivery_failures_alarm_name = "${local.resource_prefix}-alarm-lambda-destination-delivery-failures"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Lesson      = "80"
  }
}
