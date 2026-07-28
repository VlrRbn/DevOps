locals {
  resource_prefix              = "${var.project_name}-${var.environment}"
  function_name                = "${local.resource_prefix}-lambda-function"
  function_execution_role_name = "${local.resource_prefix}-role-lambda-execution"
  lambda_caller_role_name      = "${local.resource_prefix}-role-lambda-caller"

  function_logs_policy_name = "${local.resource_prefix}-policy-for-role-lambda-execution-allow-write-logs"
  caller_invoke_policy_name = "${local.resource_prefix}-policy-for-role-lambda-caller-allow-invoke-function"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Lesson      = "79"
  }
}
