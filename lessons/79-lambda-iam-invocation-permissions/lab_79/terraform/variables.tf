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
  default     = "lab79"

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

variable "operator_iam_principal_arn" {
  description = "Existing IAM user or role ARN allowed to assume the Lambda caller role"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:(role|user)/.+$", var.operator_iam_principal_arn))
    error_message = "operator_iam_principal_arn must be an IAM role or user ARN, not an STS assumed-role session ARN."
  }
}

variable "invoke_permission_mode" {
  description = "Where lambda:InvokeFunction is granted: none, lambda_caller_identity_policy, or function_resource_policy"
  type        = string
  default     = "none"

  validation {
    condition = contains(
      ["none", "lambda_caller_identity_policy", "function_resource_policy"],
      var.invoke_permission_mode,
    )
    error_message = "invoke_permission_mode must be none, lambda_caller_identity_policy, or function_resource_policy."
  }
}
