output "alb_dns_name" {
  description = "Open this in a browser"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "For the Route 53 alias record (Week 3)"
  value       = aws_lb.this.zone_id
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.this.arn
}

output "web_instance_id" {
  description = "Web EC2 instance ID"
  value       = aws_instance.web.id
}

output "web_private_ip" {
  description = "Web EC2 private IP (connectivity tests)"
  value       = aws_instance.web.private_ip
}

output "ec2_profile_name" {
  description = "SSM instance profile reused by every lab instance"
  value       = aws_iam_instance_profile.ec2.name
}

output "ec2_role_name" {
  description = "Instance role (revoke sessions during IR)"
  value       = aws_iam_role.ec2.name
}

output "ec2_sg_id" {
  description = "Web tier security group"
  value       = aws_security_group.ec2.id
}

output "db_endpoint" {
  description = "RDS hostname"
  value       = aws_db_instance.this.address
}

output "db_secret_arn" {
  description = "Secrets Manager ARN holding the DB password"
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}
