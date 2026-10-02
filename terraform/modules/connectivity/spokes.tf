# Two isolated spoke VPCs with NO internet and NO NAT. They are reached only from the hub.
resource "aws_vpc" "spoke" {
  for_each             = var.spokes
  cidr_block           = each.value
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name}-spoke-${each.key}" }
}

resource "aws_default_security_group" "spoke" {
  for_each = var.spokes
  vpc_id   = aws_vpc.spoke[each.key].id
}

resource "aws_subnet" "spoke" {
  for_each          = var.spokes
  vpc_id            = aws_vpc.spoke[each.key].id
  cidr_block        = cidrsubnet(each.value, 8, 1) # 10.x.1.0/24
  availability_zone = var.az
  tags              = { Name = "${var.name}-spoke-${each.key}-subnet" }
}

resource "aws_route_table" "spoke" {
  for_each = var.spokes
  vpc_id   = aws_vpc.spoke[each.key].id
  tags     = { Name = "${var.name}-spoke-${each.key}-rt" }
}

resource "aws_route_table_association" "spoke" {
  for_each       = var.spokes
  subnet_id      = aws_subnet.spoke[each.key].id
  route_table_id = aws_route_table.spoke[each.key].id
}
