mock_provider "aws" {
  # Mocked IAM policy documents must still be syntactically valid JSON.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

run "table_has_idempotency_contract" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.idempotency.hash_key == "idempotency_key"
    error_message = "The table partition key must be idempotency_key."
  }

  assert {
    condition     = aws_dynamodb_table.idempotency.billing_mode == "PAY_PER_REQUEST"
    error_message = "The small lab table must use on-demand billing."
  }

  assert {
    condition     = aws_dynamodb_table.idempotency.ttl[0].enabled
    error_message = "TTL must be enabled for bounded record retention."
  }

  assert {
    condition     = aws_dynamodb_table.idempotency.ttl[0].attribute_name == "expires_at"
    error_message = "The runtime and DynamoDB TTL attribute must both be expires_at."
  }
}

run "lambda_receives_exact_table_and_ttl_settings" {
  command = plan

  assert {
    condition     = aws_lambda_function.idempotent_worker.environment[0].variables["IDEMPOTENCY_TABLE_NAME"] == aws_dynamodb_table.idempotency.name
    error_message = "Lambda must receive the Terraform-managed table name."
  }

  assert {
    condition     = aws_lambda_function.idempotent_worker.environment[0].variables["CLAIM_TTL_SECONDS"] == "300"
    error_message = "The default claim lifetime must be 300 seconds."
  }

  assert {
    condition     = aws_lambda_function.idempotent_worker.environment[0].variables["RECORD_TTL_SECONDS"] == "86400"
    error_message = "The default completed-record retention must be one day."
  }
}

run "observability_and_retention_are_bounded" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.function.retention_in_days == 7
    error_message = "Function logs must have bounded retention."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.function_errors.metric_name == "Errors"
    error_message = "Handler failures must be visible through the Errors metric."
  }
}

run "ttl_overrides_are_preserved" {
  command = plan

  variables {
    claim_ttl_seconds  = 60
    record_ttl_seconds = 3600
  }

  assert {
    condition     = aws_lambda_function.idempotent_worker.environment[0].variables["CLAIM_TTL_SECONDS"] == "60"
    error_message = "A valid claim TTL override must reach the function."
  }

  assert {
    condition     = aws_lambda_function.idempotent_worker.environment[0].variables["RECORD_TTL_SECONDS"] == "3600"
    error_message = "A valid record TTL override must reach the function."
  }
}
