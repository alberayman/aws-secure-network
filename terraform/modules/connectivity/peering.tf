# Hub <-> Spoke A over VPC peering. Peering is NOT transitive: Spoke A can never reach
# Spoke B or on-prem through the hub. That is a test case in the Week 2 matrix.
resource "aws_vpc_peering_connection" "hub_a" {
  vpc_id      = var.hub_vpc_id
  peer_vpc_id = aws_vpc.spoke["a"].id
  auto_accept = true # same account + same region
  tags        = { Name = "${var.name}-hub-spoke-a" }
}

resource "aws_route" "hub_to_a" {
  route_table_id            = var.hub_private_route_table_id
  destination_cidr_block    = var.spokes["a"]
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_a.id
}

resource "aws_route" "a_to_hub" {
  route_table_id            = aws_route_table.spoke["a"].id
  destination_cidr_block    = var.hub_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.hub_a.id
}
