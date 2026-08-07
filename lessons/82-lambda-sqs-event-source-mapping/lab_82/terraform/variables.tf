variable "aws_region" {
  description = "AWS Region for the Lambda and SQS lab"
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
  default     = "lab82"

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

variable "function_timeout_seconds" {
  description = "Maximum runtime of one Lambda batch invocation"
  type        = number
  default     = 10

  validation {
    condition     = var.function_timeout_seconds >= 3 && var.function_timeout_seconds <= 60
    error_message = "function_timeout_seconds must be between 3 and 60."
  }
}

variable "queue_visibility_timeout_seconds" {
  description = "How long a received message stays hidden before retry"
  type        = number
  default     = 70

  validation {
    condition     = var.queue_visibility_timeout_seconds >= 30 && var.queue_visibility_timeout_seconds <= 43200
    error_message = "queue_visibility_timeout_seconds must be between 30 and 43200."
  }
}

variable "batch_size" {
  description = "Maximum number of SQS records delivered in one Lambda batch"
  type        = number
  default     = 5

  validation {
    condition     = var.batch_size >= 1 && var.batch_size <= 10 && floor(var.batch_size) == var.batch_size
    error_message = "batch_size must be an integer between 1 and 10."
  }
}

variable "maximum_batching_window_seconds" {
  description = "Maximum time Lambda may buffer records before invoking the function"
  type        = number
  default     = 5

  validation {
    condition     = var.maximum_batching_window_seconds >= 0 && var.maximum_batching_window_seconds <= 300
    error_message = "maximum_batching_window_seconds must be between 0 and 300."
  }
}

variable "max_receive_count" {
  description = "Receive attempts before SQS moves a message to the DLQ"
  type        = number
  default     = 3

  validation {
    condition     = var.max_receive_count >= 2 && var.max_receive_count <= 10 && floor(var.max_receive_count) == var.max_receive_count
    error_message = "max_receive_count must be an integer between 2 and 10."
  }
}
