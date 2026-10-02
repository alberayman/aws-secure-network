# Week 2 (Member 4): spokes have no internet, so SSM works through interface endpoints.
# The S3 gateway endpoint in the hub is free and keeps S3 traffic off the NAT.

data "aws_region" "current" {}

locals {
  ssm_services = ["ssm", "ssmmessages", "ec2messages"]
  endpoint_pairs = local.hybrid ? {
    for pair in setproduct(keys(local.spoke_cidrs), local.ssm_services) :
    "${pair[0]}-${pair[1]}" => { spoke = pair[0], svc = pair[1] }
  } : {}
}

resource "aws_security_group" "endpoint" {
  for_each    = local.hybrid ? local.spoke_cidrs : {}
  name        = "${var.name}-endpoint-sg-${each.key}"
  description = "HTTPS to interface endpoints"
  vpc_id      = module.connectivity[0].spoke_vpc_ids[each.key]
  tags        = { Name = "${var.name}-endpoint-sg-${each.key}" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_https" {
  for_each          = local.hybrid ? local.spoke_cidrs : {}
  security_group_id = aws_security_group.endpoint[each.key].id
  description       = "HTTPS from inside the spoke"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_endpoint" "ssm" {
  for_each            = local.endpoint_pairs
  vpc_id              = module.connectivity[0].spoke_vpc_ids[each.value.spoke]
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value.svc}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [module.connectivity[0].spoke_subnet_ids[each.value.spoke]]
  security_group_ids  = [aws_security_group.endpoint[each.value.spoke].id]
  private_dns_enabled = true
  tags                = { Name = "${var.name}-vpce-${each.key}" }
}

resource "aws_vpc_endpoint" "s3" {
  count             = local.hybrid ? 1 : 0
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [module.vpc.private_route_table_id]
  tags              = { Name = "${var.name}-vpce-s3" }
}
