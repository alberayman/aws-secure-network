# Week 2 (Member 2): one test instance per spoke. Spoke B serves a page on port 80
# (python http.server, no internet needed) for the TGW and PrivateLink tests.

resource "aws_security_group" "spoke_test" {
  for_each    = local.hybrid ? local.spoke_cidrs : {}
  name        = "${var.name}-test-sg-${each.key}"
  description = "Test instance: ICMP and HTTP from AWS networks and on-prem"
  vpc_id      = module.connectivity[0].spoke_vpc_ids[each.key]
  tags        = { Name = "${var.name}-test-sg-${each.key}" }
}

resource "aws_vpc_security_group_ingress_rule" "spoke_icmp" {
  for_each          = { for p in setproduct(local.hybrid ? keys(local.spoke_cidrs) : [], ["10.0.0.0/8", local.onprem_cidr]) : "${p[0]}-${p[1]}" => { spoke = p[0], cidr = p[1] } }
  security_group_id = aws_security_group.spoke_test[each.value.spoke].id
  description       = "Ping for the test matrix"
  cidr_ipv4         = each.value.cidr
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
}

resource "aws_vpc_security_group_ingress_rule" "spoke_http" {
  for_each          = { for p in setproduct(local.hybrid ? keys(local.spoke_cidrs) : [], ["10.0.0.0/8", local.onprem_cidr]) : "${p[0]}-${p[1]}" => { spoke = p[0], cidr = p[1] } }
  security_group_id = aws_security_group.spoke_test[each.value.spoke].id
  description       = "HTTP for the test matrix and the NLB"
  cidr_ipv4         = each.value.cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "spoke_all" {
  for_each          = local.hybrid ? local.spoke_cidrs : {}
  security_group_id = aws_security_group.spoke_test[each.key].id
  description       = "All outbound (stays inside AWS: no internet route)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "spoke" {
  for_each               = local.hybrid ? local.spoke_cidrs : {}
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = module.connectivity[0].spoke_subnet_ids[each.key]
  vpc_security_group_ids = [aws_security_group.spoke_test[each.key].id]
  iam_instance_profile   = module.compute.ec2_profile_name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOT
    #!/bin/bash
    mkdir -p /srv/web && cd /srv/web
    echo "Spoke ${upper(each.key)} service" > index.html
    nohup python3 -m http.server 80 >/dev/null 2>&1 &
  EOT

  tags = { Name = "${var.name}-spoke-${each.key}-test" }
}
