# Week 4 (Member 3): copy the victim's packets (VXLAN, UDP 4789) to an Ubuntu box with
# tcpdump and Suricata. Small hourly cost: switch off right after the capture.

locals {
  mirror = var.enable_ir && var.enable_mirroring
}

data "aws_ssm_parameter" "ubuntu" {
  count = local.mirror ? 1 : 0
  name  = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "aws_security_group" "mirror" {
  count       = local.mirror ? 1 : 0
  name        = "${var.name}-mirror-sg"
  description = "VXLAN from mirrored traffic"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.name}-mirror-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "mirror_vxlan" {
  count             = local.mirror ? 1 : 0
  security_group_id = aws_security_group.mirror[0].id
  description       = "VXLAN mirror traffic"
  cidr_ipv4         = local.hub_cidr
  from_port         = 4789
  to_port           = 4789
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_egress_rule" "mirror_all" {
  count             = local.mirror ? 1 : 0
  security_group_id = aws_security_group.mirror[0].id
  description       = "Outbound for apt and SSM"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "mirror_target" {
  count                  = local.mirror ? 1 : 0
  ami                    = data.aws_ssm_parameter.ubuntu[0].value
  instance_type          = "t3.micro" # Nitro: required for Traffic Mirroring
  subnet_id              = module.vpc.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.mirror[0].id]
  iam_instance_profile   = module.compute.ec2_profile_name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOT
    #!/bin/bash
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y tcpdump suricata
  EOT

  tags = { Name = "${var.name}-mirror-target" }
}

resource "aws_ec2_traffic_mirror_target" "this" {
  count                = local.mirror ? 1 : 0
  network_interface_id = aws_instance.mirror_target[0].primary_network_interface_id
  description          = "${var.name} mirror target"
}

resource "aws_ec2_traffic_mirror_filter" "all" {
  count       = local.mirror ? 1 : 0
  description = "mirror everything"
}

resource "aws_ec2_traffic_mirror_filter_rule" "rules" {
  for_each                 = local.mirror ? toset(["ingress", "egress"]) : toset([])
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.all[0].id
  traffic_direction        = each.key
  rule_number              = 100
  rule_action              = "accept"
  source_cidr_block        = "0.0.0.0/0"
  destination_cidr_block   = "0.0.0.0/0"
}

resource "aws_ec2_traffic_mirror_session" "victim" {
  count                    = local.mirror ? 1 : 0
  network_interface_id     = aws_instance.victim[0].primary_network_interface_id
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.all[0].id
  traffic_mirror_target_id = aws_ec2_traffic_mirror_target.this[0].id
  session_number           = 1
}
