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

output "public_subnet_ids_map" {
  description = "Public subnet IDs map"
  value       = { for k, s in aws_subnet.public_subnet : k => s.id }
}

output "security_groups" {
  description = "Security Group IDs"
  value = {
    bastion_sg = aws_security_group.bastion.id
    web_sg     = aws_security_group.web.id
    db_sg      = aws_security_group.db.id
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
