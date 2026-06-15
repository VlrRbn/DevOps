output "vpc_id" {
  description = "VPC ID for the lab network"
  value       = aws_vpc.main.id
}

output "project_name" {
  description = "Project/resource prefix represented by this module instance"
  value       = var.project_name
}

output "environment" {
  description = "Environment represented by this module instance"
  value       = var.environment
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ordered by subnet key)"
  value       = [for k in sort(keys(aws_subnet.public_subnet)) : aws_subnet.public_subnet[k].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs (ordered by subnet key)"
  value       = [for k in sort(keys(aws_subnet.private_subnet)) : aws_subnet.private_subnet[k].id]
}

output "security_groups" {
  description = "Security group IDs for web, ssm endpoints/proxy, and alb"
  value = {
    web_sg = aws_security_group.web.id
    #   db_sg           = aws_security_group.db.id
    ssm_endpoint_sg = aws_security_group.ssm_endpoint.id
    ssm_proxy_sg    = aws_security_group.ssm_proxy.id
    alb_sg          = aws_security_group.alb.id
  }
}

output "azs" {
  description = "Availability zones used by the subnets"
  value       = local.azs
}

output "web_asg_name" {
  description = "Auto Scaling Group name for the rolling web fleet"
  value       = aws_autoscaling_group.web.name
}

output "web_asg_arn" {
  description = "Auto Scaling Group ARN for the rolling web fleet"
  value       = aws_autoscaling_group.web.arn
}

output "ssm_proxy_instance_id" {
  description = "Instance ID of the SSM proxy"
  value       = aws_instance.ssm_proxy.id
}

output "ssm_proxy_private_ip" {
  description = "Private IP of the SSM proxy"
  value       = aws_instance.ssm_proxy.private_ip
}

output "alb_dns_name" {
  description = "DNS name of the internal ALB (reach via SSM port forwarding)"
  value       = aws_lb.app.dns_name

  precondition {
    condition     = aws_lb.app.dns_name != ""
    error_message = "alb_dns_name output contract requires a non-empty ALB DNS name."
  }
}

output "alb_arn" {
  description = "ARN of the internal ALB"
  value       = aws_lb.app.arn
}

output "web_tg_arn" {
  description = "ARN of the web target group"
  value       = aws_lb_target_group.web.arn

  precondition {
    condition     = startswith(aws_lb_target_group.web.arn, "arn:")
    error_message = "web_tg_arn output contract requires a valid ARN-shaped value."
  }
}

output "ssm_vpc_endpoint_ids" {
  description = "Private interface VPC endpoint IDs keyed by service (empty if disabled)"
  value       = { for k, ep in aws_vpc_endpoint.ssm : k => ep.id }
}

output "tf_plan_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC Terraform plan workflow"
  value       = aws_iam_role.github_actions_plan_role.arn
}

output "tf_apply_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC Terraform apply workflow"
  value       = aws_iam_role.github_actions_apply_role.arn
}

output "demo_api_token_parameter_name" {
  description = "SSM parameter name for lesson 71. This exposes only metadata."
  value       = var.demo_api_token_parameter_name
}

output "demo_app_secret_name" {
  description = "Secrets Manager secret name for lesson 71. This exposes only metadata."
  value       = var.demo_app_secret_name
}
