# Security-group chaining: Internet -> ALB:80 -> EC2:80 -> RDS:3306. No SSH anywhere.

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "ALB: HTTP from internet"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb-sg" }
}

resource "aws_security_group" "ec2" {
  name        = "${var.name}-ec2-sg"
  description = "EC2: HTTP only from ALB"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-ec2-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "RDS: MySQL only from EC2"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-rds-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet (lab). Production: HTTPS 443 + ACM cert."
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ec2" {
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB to web targets only"
  referenced_security_group_id = aws_security_group.ec2.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ec2_from_alb" {
  security_group_id            = aws_security_group.ec2.id
  description                  = "HTTP from the ALB security group only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

# Week 2: allow ping from spokes and on-prem for the connectivity test matrix
resource "aws_vpc_security_group_ingress_rule" "ec2_icmp_internal" {
  for_each          = toset(var.internal_cidrs)
  security_group_id = aws_security_group.ec2.id
  description       = "ICMP from internal networks (connectivity tests)"
  cidr_ipv4         = each.value
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
}

# Outbound open so SSM and package updates work through the NAT.
# Hardening idea for the final report: restrict to 443 + 3306 + VPC CIDRs.
resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  description       = "All outbound (SSM, updates via NAT)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ec2" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from the web tier only"
  referenced_security_group_id = aws_security_group.ec2.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}
