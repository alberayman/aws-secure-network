# Week 3 (Member 1): private DNS name for the app + a Route 53 health check on the ALB.

resource "aws_route53_zone" "private" {
  count = var.enable_edge ? 1 : 0
  name  = "secnet.internal"
  vpc {
    vpc_id = module.vpc.vpc_id
  }
}

resource "aws_route53_record" "app" {
  count   = var.enable_edge ? 1 : 0
  zone_id = aws_route53_zone.private[0].zone_id
  name    = "app.secnet.internal"
  type    = "A"
  alias {
    name                   = module.compute.alb_dns_name
    zone_id                = module.compute.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_health_check" "alb" {
  count             = var.enable_edge ? 1 : 0
  fqdn              = module.compute.alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  request_interval  = 30
  failure_threshold = 3
  tags              = { Name = "${var.name}-alb-health" }
}
