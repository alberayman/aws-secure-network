# Week 2 optional lab (Member 3): AWS Client VPN = remote-access VPN for individual users,
# with mutual-TLS certificate authentication. Users get an address from client_vpn_cidr and are
# source-NATed to the endpoint ENI in the hub, so hub SGs/NACLs see a 10.0.x.x address.

locals {
  client_vpn = var.enable_client_vpn && var.client_vpn_server_cert_arn != "" && var.client_vpn_client_ca_arn != ""
}

resource "aws_cloudwatch_log_group" "client_vpn" {
  count             = local.client_vpn ? 1 : 0
  name              = "/${var.name}/client-vpn"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "client_vpn" {
  count          = local.client_vpn ? 1 : 0
  name           = "connections"
  log_group_name = aws_cloudwatch_log_group.client_vpn[0].name
}

resource "aws_security_group" "client_vpn" {
  count       = local.client_vpn ? 1 : 0
  name        = "${var.name}-client-vpn-sg"
  description = "Client VPN endpoint ENIs in the hub"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.name}-client-vpn-sg" }
}

resource "aws_vpc_security_group_egress_rule" "client_vpn_to_hub" {
  count             = local.client_vpn ? 1 : 0
  security_group_id = aws_security_group.client_vpn[0].id
  description       = "VPN users may reach the hub only"
  cidr_ipv4         = local.hub_cidr
  ip_protocol       = "-1"
}

resource "aws_ec2_client_vpn_endpoint" "this" {
  count                  = local.client_vpn ? 1 : 0
  description            = "${var.name} remote access"
  server_certificate_arn = var.client_vpn_server_cert_arn
  client_cidr_block      = var.client_vpn_cidr
  split_tunnel           = true # only AWS-bound traffic goes through the tunnel
  transport_protocol     = "udp"
  vpc_id                 = module.vpc.vpc_id
  security_group_ids     = [aws_security_group.client_vpn[0].id]
  session_timeout_hours  = 8

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = var.client_vpn_client_ca_arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.client_vpn[0].name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.client_vpn[0].name
  }

  client_login_banner_options {
    enabled     = true
    banner_text = "DEPI ONL5_ISS11_G1 lab. Authorised team members only. Connections are logged."
  }

  tags = { Name = "${var.name}-client-vpn" }
}

# One subnet association = one AZ (cheapest). Production: one per AZ.
resource "aws_ec2_client_vpn_network_association" "hub" {
  count                  = local.client_vpn ? 1 : 0
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this[0].id
  subnet_id              = module.vpc.private_subnet_ids[0]
}

# Least privilege: VPN users are authorised for the hub VPC only, not the spokes or the office.
resource "aws_ec2_client_vpn_authorization_rule" "hub" {
  count                  = local.client_vpn ? 1 : 0
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this[0].id
  target_network_cidr    = local.hub_cidr
  authorize_all_groups   = true
  description            = "Hub VPC only"
}
