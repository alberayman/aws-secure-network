# Hub-and-spoke with a Transit Gateway: hub + Spoke B + the VPN attach to it.
resource "aws_ec2_transit_gateway" "this" {
  description                     = "${var.name} hub"
  amazon_side_asn                 = 64512
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags                            = { Name = "${var.name}-tgw" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = var.hub_vpc_id
  subnet_ids         = var.hub_private_subnet_ids
  tags               = { Name = "${var.name}-tgw-att-hub" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke_b" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = aws_vpc.spoke["b"].id
  subnet_ids         = [aws_subnet.spoke["b"].id]
  tags               = { Name = "${var.name}-tgw-att-spoke-b" }
}

resource "aws_route" "hub_to_b" {
  route_table_id         = var.hub_private_route_table_id
  destination_cidr_block = var.spokes["b"]
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route" "b_to_hub" {
  route_table_id         = aws_route_table.spoke["b"].id
  destination_cidr_block = var.hub_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.spoke_b]
}

resource "aws_route" "hub_to_onprem" {
  count                  = var.enable_vpn ? 1 : 0
  route_table_id         = var.hub_private_route_table_id
  destination_cidr_block = var.onprem_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.hub]
}
