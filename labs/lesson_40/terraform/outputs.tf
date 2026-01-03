output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "public_subnet_ids_map" {
  value = module.network.public_subnet_ids_map
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
