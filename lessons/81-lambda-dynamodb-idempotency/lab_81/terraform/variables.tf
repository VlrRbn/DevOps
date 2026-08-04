variable "aws_region" {
  description = "AWS Region for the Lambda and DynamoDB lab"
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must look like eu-west-1."
  }
}

variable "project_name" {
  description = "Short project name used in resource names and tags"
  type        = string
  default     = "lab81"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 3-21 lowercase letters, numbers, or dashes and start with a letter."
  }
}

variable "environment" {
  description = "Environment label used in names and runtime configuration"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage, or prod."
  }
}

variable "claim_ttl_seconds" {
  description = "How long an IN_PROGRESS claim remains owned by one invocation"
  type        = number
  default     = 300

  validation {
    condition     = var.claim_ttl_seconds >= 30 && var.claim_ttl_seconds <= 3600
    error_message = "claim_ttl_seconds must be between 30 and 3600."
  }
}

variable "record_ttl_seconds" {
  description = "How long a COMPLETED result remains available for replay"
  type        = number
  default     = 86400

  validation {
    condition     = var.record_ttl_seconds >= 3600 && var.record_ttl_seconds <= 604800
    error_message = "record_ttl_seconds must be between 3600 and 604800."
  }
}
