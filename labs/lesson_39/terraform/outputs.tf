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
    bastion_sg = aws_security_group.bastion.id
    web_sg     = aws_security_group.web.id
    db_sg      = aws_security_group.db.id
  }
}