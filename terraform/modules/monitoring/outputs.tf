output "logs_bucket_name" {
  description = "Central log bucket"
  value       = aws_s3_bucket.logs.id
}

output "logs_bucket_arn" {
  description = "Central log bucket ARN"
  value       = aws_s3_bucket.logs.arn
}

output "trail_arn" {
  description = "CloudTrail ARN"
  value       = aws_cloudtrail.this.arn
}

output "athena_workgroup" {
  description = "Use this workgroup in the Athena console"
  value       = aws_athena_workgroup.this.name
}

output "athena_database" {
  description = "Athena database holding vpc_flow_logs"
  value       = aws_athena_database.this.name
}

output "network_alerts_topic_arn" {
  description = "SNS topic for network alarms (eu-west-1)"
  value       = aws_sns_topic.network_alerts.arn
}
