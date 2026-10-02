# Simulated office: a VPC with a strongSwan EC2 acting as the customer router,
# connected to the Transit Gateway with an AWS Site-to-Site VPN (2 IPsec tunnels).

resource "aws_vpc" "onprem" {
  count                = var.enable_vpn ? 1 : 0
  cidr_block           = var.onprem_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name}-onprem" }
}

resource "aws_default_security_group" "onprem" {
  count  = var.enable_vpn ? 1 : 0
  vpc_id = aws_vpc.onprem[0].id
}

resource "aws_internet_gateway" "onprem" {
  count  = var.enable_vpn ? 1 : 0
  vpc_id = aws_vpc.onprem[0].id
  tags   = { Name = "${var.name}-onprem-igw" }
}

resource "aws_subnet" "onprem" {
  count             = var.enable_vpn ? 1 : 0
  vpc_id            = aws_vpc.onprem[0].id
  cidr_block        = cidrsubnet(var.onprem_cidr, 8, 1) # 192.168.1.0/24
  availability_zone = var.az
  tags              = { Name = "${var.name}-onprem-subnet" }
}

resource "aws_route_table" "onprem" {
  count  = var.enable_vpn ? 1 : 0
  vpc_id = aws_vpc.onprem[0].id
  tags   = { Name = "${var.name}-onprem-rt" }
}

resource "aws_route" "onprem_default" {
  count                  = var.enable_vpn ? 1 : 0
  route_table_id         = aws_route_table.onprem[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.onprem[0].id
}

# Other "office" hosts reach AWS through the router instance
resource "aws_route" "onprem_to_aws" {
  count                  = var.enable_vpn ? 1 : 0
  route_table_id         = aws_route_table.onprem[0].id
  destination_cidr_block = "10.0.0.0/8"
  network_interface_id   = aws_instance.strongswan[0].primary_network_interface_id
}

resource "aws_route_table_association" "onprem" {
  count          = var.enable_vpn ? 1 : 0
  subnet_id      = aws_subnet.onprem[0].id
  route_table_id = aws_route_table.onprem[0].id
}

resource "aws_security_group" "strongswan" {
  count       = var.enable_vpn ? 1 : 0
  name        = "${var.name}-strongswan-sg"
  description = "IPsec for the on-prem router"
  vpc_id      = aws_vpc.onprem[0].id
  tags        = { Name = "${var.name}-strongswan-sg" }
}

# Lab shortcut: IKE/NAT-T/ESP from anywhere. Tighten to the two tunnel outside IPs
# (aws_vpn_connection.this[0].tunnel1_address / tunnel2_address) once the VPN exists.
resource "aws_vpc_security_group_ingress_rule" "ike" {
  count             = var.enable_vpn ? 1 : 0
  security_group_id = aws_security_group.strongswan[0].id
  description       = "IKE"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 500
  to_port           = 500
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_ingress_rule" "natt" {
  count             = var.enable_vpn ? 1 : 0
  security_group_id = aws_security_group.strongswan[0].id
  description       = "IPsec NAT-T"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 4500
  to_port           = 4500
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_ingress_rule" "esp" {
  count             = var.enable_vpn ? 1 : 0
  security_group_id = aws_security_group.strongswan[0].id
  description       = "ESP"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "50"
}

resource "aws_vpc_security_group_ingress_rule" "icmp" {
  count             = var.enable_vpn ? 1 : 0
  security_group_id = aws_security_group.strongswan[0].id
  description       = "Ping from AWS networks"
  cidr_ipv4         = "10.0.0.0/8"
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  count             = var.enable_vpn ? 1 : 0
  security_group_id = aws_security_group.strongswan[0].id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

data "aws_ssm_parameter" "ubuntu" {
  count = var.enable_vpn ? 1 : 0
  name  = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "aws_instance" "strongswan" {
  count                       = var.enable_vpn ? 1 : 0
  ami                         = data.aws_ssm_parameter.ubuntu[0].value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.onprem[0].id
  vpc_security_group_ids      = [aws_security_group.strongswan[0].id]
  iam_instance_profile        = var.instance_profile_name
  associate_public_ip_address = true  # needed at boot for apt; the EIP replaces it after
  source_dest_check           = false # it routes traffic for other hosts

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOT
    #!/bin/bash
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y strongswan strongswan-starter
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
  EOT

  tags = { Name = "${var.name}-strongswan" }
}

resource "aws_eip" "strongswan" {
  count    = var.enable_vpn ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.strongswan[0].id
  tags     = { Name = "${var.name}-strongswan-eip" }
}

resource "aws_customer_gateway" "onprem" {
  count      = var.enable_vpn ? 1 : 0
  bgp_asn    = 65000
  ip_address = aws_eip.strongswan[0].public_ip
  type       = "ipsec.1"
  tags       = { Name = "${var.name}-cgw" }
}

resource "aws_vpn_connection" "this" {
  count               = var.enable_vpn ? 1 : 0
  customer_gateway_id = aws_customer_gateway.onprem[0].id
  transit_gateway_id  = aws_ec2_transit_gateway.this.id
  type                = "ipsec.1"
  static_routes_only  = true

  # Traffic selectors for a policy-based strongSwan: office <-> all AWS 10.x networks
  local_ipv4_network_cidr  = var.onprem_cidr
  remote_ipv4_network_cidr = "10.0.0.0/8"
  tags                     = { Name = "${var.name}-vpn" }
}

resource "aws_ec2_transit_gateway_route" "to_onprem" {
  count                          = var.enable_vpn ? 1 : 0
  destination_cidr_block         = var.onprem_cidr
  transit_gateway_attachment_id  = aws_vpn_connection.this[0].transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.this.association_default_route_table_id
}
