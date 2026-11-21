# Hub-and-spoke with a Transit Gateway: hub + Spoke B + the VPN attach to it.
# Segmentation: no default route table. Each attachment gets its own table (see below), so the
# office and Spoke B can reach the hub but never each other.
resource "aws_ec2_transit_gateway" "this" {
  description                     = "${var.name} hub"
  amazon_side_asn                 = 64512
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags                            = { Name = "${var.name}-tgw" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = var.hub_vpc_id
  subnet_ids         = var.hub_tgw_subnet_ids # own /28s, so the private NACL filters TGW traffic
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

# ---------- TGW route tables (segmentation) ----------
# hub-rt     <- hub attachment:     learns Spoke B (propagation) + static route to the office
# spokes-rt  <- Spoke B attachment: learns the hub only
# onprem-rt  <- VPN attachment:     learns the hub only  => office -> Spoke B has no route
resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "${var.name}-tgw-rt-hub" }
}

resource "aws_ec2_transit_gateway_route_table" "spokes" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "${var.name}-tgw-rt-spokes" }
}

resource "aws_ec2_transit_gateway_route_table" "onprem" {
  count              = var.enable_vpn ? 1 : 0
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "${var.name}-tgw-rt-onprem" }
}

resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke_b" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke_b.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes.id
}

resource "aws_ec2_transit_gateway_route_table_association" "vpn" {
  count                          = var.enable_vpn ? 1 : 0
  transit_gateway_attachment_id  = aws_vpn_connection.this[0].transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.onprem[0].id
}

# Spoke B's CIDR is learned by the hub table only
resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_b_to_hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke_b.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

# The hub's CIDR is learned by the spokes table and the office table
resource "aws_ec2_transit_gateway_route_table_propagation" "hub_to_spokes" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "hub_to_onprem" {
  count                          = var.enable_vpn ? 1 : 0
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.onprem[0].id
}
