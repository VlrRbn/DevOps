output "vpc_id" {
  description = "VPC ID for the lab network"
  value       = aws_vpc.main.id
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
  description = "Security group IDs for web, db, ssm endpoints/proxy, and alb"
  value = {
    web_sg          = aws_security_group.web.id
    db_sg           = aws_security_group.db.id
    ssm_endpoint_sg = aws_security_group.ssm_endpoint.id
    ssm_proxy_sg    = aws_security_group.ssm_proxy.id
    alb_sg          = aws_security_group.alb.id
  }
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs keyed by public subnet key (empty if NAT disabled)"
  value       = { for k, ngw in aws_nat_gateway.nat_gw : k => ngw.id }
}

output "azs" {
  description = "Availability zones used by the subnets"
  value       = local.azs
}

output "web_asg_names" {
  description = "Auto Scaling Group names for web (blue/green)"
  value       = { for k, asg in aws_autoscaling_group.web : k => asg.name }
}

output "web_asg_arns" {
  description = "Auto Scaling Group ARNs for web (blue/green)"
  value       = { for k, asg in aws_autoscaling_group.web : k => asg.arn }
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
}

output "alb_arn" {
  description = "ARN of the internal ALB"
  value       = aws_lb.app.arn
}

output "web_tg_arns" {
  description = "ARNs of the web target groups (blue/green)"
  value       = { for k, tg in aws_lb_target_group.web : k => tg.arn }
}

output "ssm_vpc_endpoint_ids" {
  description = "SSM VPC endpoint IDs keyed by service (empty if disabled)"
  value       = { for k, ep in aws_vpc_endpoint.ssm : k => ep.id }
}
