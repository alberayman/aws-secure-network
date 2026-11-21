# Week 3 (Member 1): private DNS zone (db.secnet.internal) + an end-to-end Route 53 health check
# on the public entry point (CloudFront -> WAF -> ALB -> web).

resource "aws_route53_zone" "private" {
  count = var.enable_edge && var.enable_compute ? 1 : 0
  name  = "secnet.internal"
  vpc {
    vpc_id = module.vpc.vpc_id
  }
}

# Internal-only name for the database: resolves to the RDS private IP, only inside the hub VPC.
# (The ALB now accepts CloudFront only, so an internal alias to it would be refused.)
resource "aws_route53_record" "db" {
  count   = var.enable_edge && var.enable_compute ? 1 : 0
  zone_id = aws_route53_zone.private[0].zone_id
  name    = "db.secnet.internal"
  type    = "CNAME"
  ttl     = 60
  records = [one(module.compute[*].db_endpoint)]
}

# End-to-end health check on the public entry point: CloudFront -> WAF -> ALB -> web server
resource "aws_route53_health_check" "alb" {
  count             = var.enable_edge && var.enable_compute ? 1 : 0
  fqdn              = module.edge[0].app_domain
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  request_interval  = 30
  failure_threshold = 3
  tags              = { Name = "${var.name}-app-health" }
}
