# Public route table with default route to IGW.
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-public_rt"
  })
}

# Associate public subnets with public route table.
resource "aws_route_table_association" "public_subnet_assoc" {
  for_each = local.public_subnet_map

  subnet_id      = aws_subnet.public_subnet[each.key].id
  route_table_id = aws_route_table.public_rt.id
}

# Private route tables without internet default route.
resource "aws_route_table" "private_rt" {
  for_each = local.private_subnet_map
  vpc_id   = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-private_rt-${each.key}"
  })
}

# Associate private subnets with private route tables.
resource "aws_route_table_association" "private_rt_assoc" {
  for_each = local.private_subnet_map

  subnet_id      = aws_subnet.private_subnet[each.key].id
  route_table_id = aws_route_table.private_rt[each.key].id
}
