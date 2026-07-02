variable "aws_region" {
  type        = string
  description = "AWS region where the CloudTrail trail is managed."
  default     = "eu-west-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must look like eu-west-1."
  }
}

variable "project_name" {
  type        = string
  description = "Short project name used in resource names and tags."
  default     = "lab77"
}

variable "trail_name" {
  type        = string
  description = "CloudTrail trail name."
  default     = "lab77-terraform-audit-trail"
}

variable "cloudtrail_log_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for CloudTrail logs."
}

variable "terraform_state_bucket_name" {
  type        = string
  description = "Existing Terraform state bucket to audit with S3 data events."
}

variable "terraform_state_prefixes" {
  type        = map(string)
  description = "Terraform state object prefix to audit. This is a map of environment names to prefixes."

  default = {
    dev   = "lab76/dev/full/"
    stage = "lab76/stage/full/"
    prod  = "lab76/prod/full/"
  }

  validation {
    condition = alltrue([
      for env in keys(var.terraform_state_prefixes) :
      contains(["dev", "stage", "prod"], env)
    ])

    error_message = "terraform_state_prefixes keys must be one of: dev, stage, prod."
  }

  validation {
    condition = alltrue([
      for prefix in values(var.terraform_state_prefixes) :
      length(prefix) > 0 && !startswith(prefix, "/")
    ])

    error_message = "Each terraform_state_prefixes value must be a non-empty S3 key prefix without a leading slash."
  }
}

variable "enable_state_data_events" {
  type        = bool
  description = "Enable S3 object-level data events for terraform_state_bucket_name/terraform_state_prefix."
  default     = true
}

variable "is_multi_region_trail" {
  type        = bool
  description = "Create a multi-region trail. Keep false for a low-noise lab; production normally uses true."
  default     = false
}

variable "log_retention_days" {
  type        = number
  description = "Days before CloudTrail log objects expire from the log bucket."
  default     = 30

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "log_retention_days must be between 1 and 365."
  }
}

variable "force_destroy_log_bucket" {
  type        = bool
  description = "Allow Terraform destroy to delete non-empty CloudTrail log bucket. Keep false unless this is a disposable lab."
  default     = false
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags for audit resources."
  default     = {}
}
