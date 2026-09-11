variable "aws_region" {
  description = "Commercial AWS Region used by this lab"
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must look like eu-west-1."
  }
}

variable "project_name" {
  description = "Short prefix for the disposable HTTP API lab"
  type        = string
  default     = "lab87"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 3-21 lowercase letters, numbers, or dashes and start with a letter."
  }
}

variable "environment" {
  description = "Naming label; this lab creates one dev deployment"
  type        = string
  default     = "dev"

  validation {
    condition     = var.environment == "dev"
    error_message = "This disposable lab supports environment=dev only."
  }
}

variable "function_timeout_seconds" {
  description = "Lambda timeout, kept below the 10-second integration timeout"
  type        = number
  default     = 6

  validation {
    condition     = var.function_timeout_seconds >= 3 && var.function_timeout_seconds <= 8 && floor(var.function_timeout_seconds) == var.function_timeout_seconds
    error_message = "Use an integer from 3 to 8 seconds."
  }
}

variable "throttle_rate_limit" {
  description = "Best-effort requests per second per route, not a cost ceiling"
  type        = number
  default     = 5

  validation {
    condition     = var.throttle_rate_limit >= 1 && var.throttle_rate_limit <= 20
    error_message = "Keep the lab route rate between 1 and 20 requests per second."
  }
}

variable "throttle_burst_limit" {
  description = "Token bucket burst target for each route"
  type        = number
  default     = 10

  validation {
    condition     = var.throttle_burst_limit >= 1 && var.throttle_burst_limit <= 40 && floor(var.throttle_burst_limit) == var.throttle_burst_limit
    error_message = "Use an integer burst target from 1 to 40."
  }
}

variable "enable_api_invoke_permission" {
  description = "Set false only during the dev integration-permission failure drill"
  type        = bool
  default     = true
}
