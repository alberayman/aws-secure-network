# Week 4 (Member 4): quarantine security group. No ingress and no egress rules:
# Terraform removes the default allow-all egress rule from aws_security_group.
resource "aws_security_group" "isolation" {
  count       = var.enable_ir ? 1 : 0
  name        = "${var.name}-isolation"
  description = "Quarantine: no inbound, no outbound"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.name}-isolation", Purpose = "incident-response" }
}
