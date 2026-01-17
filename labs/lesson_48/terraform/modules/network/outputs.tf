output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = [for k in sort(keys(aws_subnet.public_subnet)) : aws_subnet.public_subnet[k].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = [for k in sort(keys(aws_subnet.private_subnet)) : aws_subnet.private_subnet[k].id]
}

output "security_groups" {
  description = "Security Group IDs"
  value = {
    web_sg          = aws_security_group.web.id
    db_sg           = aws_security_group.db.id
    ssm_endpoint_sg = aws_security_group.ssm_endpoint.id
    ssm_proxy_sg    = aws_security_group.ssm_proxy.id
    alb_sg          = aws_security_group.alb.id
  }
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs"
  value       = { for k, ngw in aws_nat_gateway.nat_gw : k => ngw.id }
}

output "azs" {
  description = "Availability Zones"
  value       = local.azs
}

output "web_private_ip" {
  description = "Private IP of Web"
  value       = aws_instance.web_a.private_ip
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer (open in browser to test)"
  value       = aws_lb.app.dns_name
}