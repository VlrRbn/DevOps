variable "aws_region" {
  description = "AWS Region for the Lambda lab"
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
  default     = "lab80"

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

variable "maximum_retry_attempts" {
  description = "Additional attempts after the first failed asynchronous invocation"
  type        = number
  default     = 1

  validation {
    condition     = contains([0, 1, 2], var.maximum_retry_attempts)
    error_message = "maximum_retry_attempts must be 0, 1, or 2."
  }
}

variable "maximum_event_age_in_seconds" {
  description = "Maximum age of an asynchronous event before Lambda discards it"
  type        = number
  default     = 300

  validation {
    condition     = var.maximum_event_age_in_seconds >= 60 && var.maximum_event_age_in_seconds <= 21600
    error_message = "maximum_event_age_in_seconds must be between 60 and 21600."
  }
}
