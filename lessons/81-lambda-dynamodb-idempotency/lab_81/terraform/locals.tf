locals {
  resource_prefix = "${var.project_name}-${var.environment}"

  function_name                = "${local.resource_prefix}-lambda-idempotent-worker"
  function_execution_role_name = "${local.resource_prefix}-role-lambda-execution"
  function_runtime_policy_name = "${local.resource_prefix}-policy-for-role-lambda-execution-allow-logs-and-idempotency-table"
  idempotency_table_name       = "${local.resource_prefix}-dynamodb-idempotency"
  function_errors_alarm_name   = "${local.resource_prefix}-alarm-lambda-errors"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Lesson      = "81"
  }
}
