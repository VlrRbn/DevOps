output "environment" {
  description = "Environment represented by this root module"
  value       = module.network.environment
}

output "project_name" {
  description = "Project/resource prefix for this environment"
  value       = module.network.project_name
}

output "tf_state_key" {
  description = "Expected remote state key for this environment"
  value       = var.tf_state_key
}

output "vpc_id" {
  description = "VPC ID for the lab network"
  value       = module.network.vpc_id
}

output "web_asg_name" {
  description = "Auto Scaling Group name for the rolling web fleet"
  value       = module.network.web_asg_name
}

output "alb_dns_name" {
  description = "DNS name of the internal ALB (reach via SSM port forwarding)"
  value       = module.network.alb_dns_name
}

output "web_tg_arn" {
  description = "ARN of the web target group"
  value       = module.network.web_tg_arn
}

output "tf_plan_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC Terraform plan workflow"
  value       = module.network.tf_plan_role_arn
}

output "tf_apply_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC Terraform apply workflow"
  value       = module.network.tf_apply_role_arn
}
