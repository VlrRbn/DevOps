mock_provider "aws" {
  # aws_iam_policy_document is local in a real plan, but a mocked provider must
  # still return syntactically valid JSON for IAM resource validation.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  operator_iam_principal_arn = "arn:aws:iam::123456789012:role/LessonOperator"
}

run "no_grant_creates_no_invoke_policy" {
  command = plan

  variables {
    invoke_permission_mode = "none"
  }

  assert {
    condition     = length(aws_iam_role_policy.lambda_caller_invoke_access) == 0
    error_message = "none mode must not attach an identity-based invoke policy."
  }

  assert {
    condition     = length(aws_lambda_permission.function_allows_lambda_caller) == 0
    error_message = "none mode must not add a Lambda resource policy statement."
  }
}

run "lambda_caller_identity_policy_mode_uses_only_role_policy" {
  command = plan

  variables {
    invoke_permission_mode = "lambda_caller_identity_policy"
  }

  assert {
    condition     = length(aws_iam_role_policy.lambda_caller_invoke_access) == 1
    error_message = "lambda_caller_identity_policy mode must attach one invoke policy to the Lambda caller role."
  }

  assert {
    condition     = length(aws_lambda_permission.function_allows_lambda_caller) == 0
    error_message = "lambda_caller_identity_policy mode must not add a Lambda resource policy statement."
  }
}

run "function_resource_policy_mode_uses_only_lambda_policy" {
  command = plan

  variables {
    invoke_permission_mode = "function_resource_policy"
  }

  assert {
    condition     = length(aws_iam_role_policy.lambda_caller_invoke_access) == 0
    error_message = "function_resource_policy mode must not attach an invoke policy to the Lambda caller role."
  }

  assert {
    condition     = length(aws_lambda_permission.function_allows_lambda_caller) == 1
    error_message = "function_resource_policy mode must add one Lambda resource policy statement."
  }
}
