output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "security_groups" {
  value = module.network.security_groups
}

output "nat_gateway_ids" {
  value = module.network.nat_gateway_ids
}

output "azs" {
  value = module.network.azs
}

output "web_private_ip" {
  value = module.network.web_private_ip
}

output "alb_dns_name" {
  value = module.network.alb_dns_name
}