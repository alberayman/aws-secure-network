output "site_bucket_name" {
  description = "Upload index.html here"
  value       = aws_s3_bucket.site.id
}

output "cloudfront_domain" {
  description = "https://<this>/index.html"
  value       = aws_cloudfront_distribution.site.domain_name
}

output "cloudfront_distribution_id" {
  description = "For cache invalidations"
  value       = aws_cloudfront_distribution.site.id
}

output "web_acl_arn" {
  description = "WAF web ACL ARN"
  value       = aws_wafv2_web_acl.site.arn
}

output "web_acl_name" {
  description = "WAF web ACL name (CloudWatch alarm dimension)"
  value       = aws_wafv2_web_acl.site.name
}
