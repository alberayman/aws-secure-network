# Week 2 (Member 4): Spoke B publishes its web service with PrivateLink; the hub consumes it
# through an interface endpoint. No routing between the VPCs is needed for this path.

resource "aws_lb" "spoke_b_nlb" {
  count              = local.hybrid ? 1 : 0
  name               = "${var.name}-spoke-b-nlb"
  load_balancer_type = "network"
  internal           = true
  subnets            = [module.connectivity[0].spoke_subnet_ids["b"]]
}

resource "aws_lb_target_group" "spoke_b" {
  count       = local.hybrid ? 1 : 0
  name        = "${var.name}-spoke-b-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = module.connectivity[0].spoke_vpc_ids["b"]
  target_type = "instance"
}

resource "aws_lb_target_group_attachment" "spoke_b" {
  count            = local.hybrid ? 1 : 0
  target_group_arn = aws_lb_target_group.spoke_b[0].arn
  target_id        = aws_instance.spoke["b"].id
  port             = 80
}

resource "aws_lb_listener" "spoke_b" {
  count             = local.hybrid ? 1 : 0
  load_balancer_arn = aws_lb.spoke_b_nlb[0].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.spoke_b[0].arn
  }
}

resource "aws_vpc_endpoint_service" "spoke_b" {
  count                      = local.hybrid ? 1 : 0
  acceptance_required        = false # lab; production = true + allowed principals
  network_load_balancer_arns = [aws_lb.spoke_b_nlb[0].arn]
  tags                       = { Name = "${var.name}-spoke-b-service" }
}

resource "aws_security_group" "privatelink_consumer" {
  count       = local.hybrid ? 1 : 0
  name        = "${var.name}-privatelink-consumer"
  description = "HTTP to the PrivateLink endpoint from the hub"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.name}-privatelink-consumer" }
}

resource "aws_vpc_security_group_ingress_rule" "privatelink_http" {
  count             = local.hybrid ? 1 : 0
  security_group_id = aws_security_group.privatelink_consumer[0].id
  description       = "HTTP from the hub"
  cidr_ipv4         = local.hub_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_endpoint" "consumer" {
  count              = local.hybrid ? 1 : 0
  vpc_id             = module.vpc.vpc_id
  service_name       = aws_vpc_endpoint_service.spoke_b[0].service_name
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [aws_security_group.privatelink_consumer[0].id]
  tags               = { Name = "${var.name}-vpce-privatelink" }
}
