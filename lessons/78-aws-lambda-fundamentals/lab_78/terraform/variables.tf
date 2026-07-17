variable "aws_region" {
  description = "AWS Region for the Lambda lab"
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must look like eu-west-1 or us-gov-west-1."
  }
}

variable "project_name" {
  description = "Short project name used in resource names and tags"
  type        = string
  default     = "lab78"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 3-21 lowercase letters, numbers, or dashes and start with a letter."
  }
}

variable "environment" {
  description = "Environment label used in resource names and runtime configuration"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage, or prod."
  }
}

variable "reserved_concurrent_executions" {
  description = "Optional Lambda concurrency reservation; leave null for an unreserved training function"
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.reserved_concurrent_executions == null ? true : (var.reserved_concurrent_executions >= 1 && floor(var.reserved_concurrent_executions) == var.reserved_concurrent_executions)
    error_message = "reserved_concurrent_executions must be null or a positive integer."
  }
}
