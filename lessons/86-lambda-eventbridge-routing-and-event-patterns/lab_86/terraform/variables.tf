variable "aws_region" {
  description = "AWS Region for the EventBridge, SQS, and Lambda routing lab"
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
  default     = "lab86"

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

variable "event_source" {
  description = "Stable EventBridge source value used by publishers and rules"
  type        = string
  default     = "com.devops.orders"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]{2,255}$", var.event_source))
    error_message = "event_source must be 3-256 supported characters and start with a letter or number."
  }
}

variable "high_value_threshold" {
  description = "Minimum order amount routed to the high-value branch"
  type        = number
  default     = 100

  validation {
    condition     = var.high_value_threshold > 0 && var.high_value_threshold <= 1000000
    error_message = "high_value_threshold must be greater than zero and no more than 1000000."
  }
}

variable "function_timeout_seconds" {
  description = "Maximum runtime of one Lambda batch invocation"
  type        = number
  default     = 6

  validation {
    condition = (
      var.function_timeout_seconds >= 3 &&
      var.function_timeout_seconds <= 60 &&
      floor(var.function_timeout_seconds) == var.function_timeout_seconds
    )
    error_message = "function_timeout_seconds must be an integer between 3 and 60."
  }
}

variable "queue_visibility_timeout_seconds" {
  description = "How long a received source message remains hidden before retry"
  type        = number
  default     = 40

  validation {
    condition = (
      var.queue_visibility_timeout_seconds >= 30 &&
      var.queue_visibility_timeout_seconds <= 43200 &&
      floor(var.queue_visibility_timeout_seconds) == var.queue_visibility_timeout_seconds
    )
    error_message = "queue_visibility_timeout_seconds must be an integer between 30 and 43200."
  }
}

variable "batch_size" {
  description = "Maximum standard SQS records delivered to one consumer invocation"
  type        = number
  default     = 5

  validation {
    condition     = var.batch_size >= 1 && var.batch_size <= 10 && floor(var.batch_size) == var.batch_size
    error_message = "batch_size must be an integer between 1 and 10 for this lab."
  }
}

variable "event_source_maximum_concurrency" {
  description = "Maximum concurrent Lambda invocations for each branch"
  type        = number
  default     = 2

  validation {
    condition = (
      var.event_source_maximum_concurrency >= 2 &&
      var.event_source_maximum_concurrency <= 1000 &&
      floor(var.event_source_maximum_concurrency) == var.event_source_maximum_concurrency
    )
    error_message = "event_source_maximum_concurrency must be an integer between 2 and 1000."
  }
}

variable "max_receive_count" {
  description = "Receive attempts before a source queue moves a failed message to its processing DLQ"
  type        = number
  default     = 3

  validation {
    condition     = var.max_receive_count >= 2 && var.max_receive_count <= 10 && floor(var.max_receive_count) == var.max_receive_count
    error_message = "max_receive_count must be an integer between 2 and 10."
  }
}

variable "target_maximum_event_age_seconds" {
  description = "Maximum EventBridge event age while target delivery is retried"
  type        = number
  default     = 3600

  validation {
    condition = (
      var.target_maximum_event_age_seconds >= 60 &&
      var.target_maximum_event_age_seconds <= 86400 &&
      floor(var.target_maximum_event_age_seconds) == var.target_maximum_event_age_seconds
    )
    error_message = "target_maximum_event_age_seconds must be an integer between 60 and 86400."
  }
}

variable "target_maximum_retry_attempts" {
  description = "Maximum EventBridge attempts after the initial target delivery fails"
  type        = number
  default     = 10

  validation {
    condition = (
      var.target_maximum_retry_attempts >= 0 &&
      var.target_maximum_retry_attempts <= 185 &&
      floor(var.target_maximum_retry_attempts) == var.target_maximum_retry_attempts
    )
    error_message = "target_maximum_retry_attempts must be an integer between 0 and 185."
  }
}
