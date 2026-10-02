# Week 4 (Member 2): the "compromised" instance, in the hub private subnet.
# isolate_victim = true swaps it onto the quarantine security group (Member 4, Guide 4.3).

resource "aws_instance" "victim" {
  count                  = var.enable_ir ? 1 : 0
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = module.vpc.private_subnet_ids[0]
  vpc_security_group_ids = var.isolate_victim ? [aws_security_group.isolation[0].id] : [module.compute.ec2_sg_id]
  iam_instance_profile   = module.compute.ec2_profile_name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name   = "${var.name}-victim"
    Case   = "IR-001"
    Status = var.isolate_victim ? "Quarantined" : "Active"
  }
}

# Baseline snapshot taken at creation. The REAL evidence snapshot is taken by hand during
# the incident (console or `aws ec2 create-snapshot`), before containment.
resource "aws_ebs_snapshot" "baseline" {
  count       = var.enable_ir ? 1 : 0
  volume_id   = aws_instance.victim[0].root_block_device[0].volume_id
  description = "baseline-${var.name}-victim"
  tags        = { Case = "IR-001", Type = "baseline" }
}
