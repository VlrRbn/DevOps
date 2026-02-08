output "vpc_id" {
  description = "VPC ID for the lab network"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ordered by subnet key)"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs (ordered by subnet key)"
  value       = module.network.private_subnet_ids
}

output "security_groups" {
  description = "Security group IDs for web, db, ssm endpoints/proxy, and alb"
  value       = module.network.security_groups
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs keyed by public subnet key (empty if NAT disabled)"
  value       = module.network.nat_gateway_ids
}

output "azs" {
  description = "Availability zones used by the subnets"
  value       = module.network.azs
}

output "web_asg_name" {
  description = "Auto Scaling Group name for the rolling web fleet"
  value       = module.network.web_asg_name
}

output "web_asg_arn" {
  description = "Auto Scaling Group ARN for the rolling web fleet"
  value       = module.network.web_asg_arn
}

output "ssm_proxy_instance_id" {
  description = "Instance ID of the SSM proxy"
  value       = module.network.ssm_proxy_instance_id
}

output "ssm_proxy_private_ip" {
  description = "Private IP of the SSM proxy"
  value       = module.network.ssm_proxy_private_ip
}

output "alb_dns_name" {
  description = "DNS name of the internal ALB (reach via SSM port forwarding)"
  value       = module.network.alb_dns_name
}

output "alb_arn" {
  description = "ARN of the internal ALB"
  value       = module.network.alb_arn
}

output "web_tg_arn" {
  description = "ARN of the web target group"
  value       = module.network.web_tg_arn
}

output "ssm_vpc_endpoint_ids" {
  description = "SSM VPC endpoint IDs keyed by service (empty if disabled)"
  value       = module.network.ssm_vpc_endpoint_ids
}
