locals {
  resource_prefix              = "${var.project_name}-${var.environment}"
  function_name                = "${local.resource_prefix}-http-function"
  function_execution_role_name = "${local.function_name}-execution-role"
  function_log_policy_name     = "${local.function_execution_role_name}-logs-policy"
  stage_name                   = "$default"

  routes = {
    health = { method = "GET", path = "health", authorization = "NONE" }
    quotes = { method = "POST", path = "quotes", authorization = "AWS_IAM" }
  }
}
