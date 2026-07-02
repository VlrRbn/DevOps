output "trail_name" {
  description = "CloudTrail trail name to pass to cloudtrail-audit-snapshot.sh --trail-name."
  value       = aws_cloudtrail.terraform_audit.name
}

output "trail_arn" {
  description = "CloudTrail trail ARN."
  value       = aws_cloudtrail.terraform_audit.arn
}

output "cloudtrail_log_bucket_name" {
  description = "S3 bucket receiving CloudTrail logs."
  value       = aws_s3_bucket.cloudtrail_logs.bucket
}

output "state_data_event_arns" {
  description = "S3 object ARN prefixes covered by CloudTrail data events."
  value       = local.state_data_event_arns
}

output "snapshot_commands" {
  description = "Example commands for collecting lesson 77 evidence with selector evidence for all Terraform state prefixes."

  value = {
    for env, prefix in local.state_data_event_prefixes :
    env => join(" ", [
      "lessons/77-cloudtrail-audit-evidence-and-portfolio-packaging/scripts/cloudtrail-audit-snapshot.sh",
      "--region", var.aws_region,
      "--state-bucket", var.terraform_state_bucket_name,
      "--state-prefix", prefix,
      "--trail-name", aws_cloudtrail.terraform_audit.name
    ])
  }
}
