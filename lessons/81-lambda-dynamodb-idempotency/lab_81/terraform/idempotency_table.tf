resource "aws_dynamodb_table" "idempotency" {
  name         = local.idempotency_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "idempotency_key"

  attribute {
    name = "idempotency_key"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }

  # This is an isolated, disposable dev lab. Production tables require an
  # explicit recovery decision such as PITR, backups, or global-table replicas.
  point_in_time_recovery {
    enabled = false
  }
}
