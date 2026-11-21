output "alb_url" {
  description = "Week 1: open in a browser"
  value       = try("http://${module.compute[0].alb_dns_name}", null)
}

output "web_instance_id" {
  description = "Week 1: Session Manager target"
  value       = one(module.compute[*].web_instance_id)
}

output "web_private_ip" {
  description = "Week 1/2: ping target for the test matrix"
  value       = one(module.compute[*].web_private_ip)
}

output "db_endpoint" {
  description = "Week 1: RDS hostname"
  value       = one(module.compute[*].db_endpoint)
}

output "db_secret_arn" {
  description = "Week 1: Secrets Manager secret with the DB password"
  value       = one(module.compute[*].db_secret_arn)
}

output "logs_bucket" {
  description = "Central log bucket (CloudTrail, Flow Logs, Athena results)"
  value       = module.monitoring.logs_bucket_name
}

output "athena_workgroup" {
  description = "Week 4: pick this workgroup in Athena"
  value       = module.monitoring.athena_workgroup
}

output "spoke_test_ips" {
  description = "Week 2: private IPs of the spoke test instances"
  value       = { for k, v in aws_instance.spoke : k => v.private_ip }
}

output "hub_vpc_id" {
  description = "Hub VPC (demo tests)"
  value       = module.vpc.vpc_id
}

output "spoke_a_instance_id" {
  description = "Week 2: Spoke A test host (SSM target for demo tests)"
  value       = try(aws_instance.spoke["a"].id, null)
}

output "spoke_b_instance_id" {
  description = "Week 2: Spoke B test host (SSM target for demo tests)"
  value       = try(aws_instance.spoke["b"].id, null)
}

output "spoke_a_ip" {
  description = "Week 2: Spoke A test host private IP"
  value       = try(aws_instance.spoke["a"].private_ip, null)
}

output "spoke_b_ip" {
  description = "Week 2: Spoke B test host private IP"
  value       = try(aws_instance.spoke["b"].private_ip, null)
}

output "strongswan_private_ip" {
  description = "Week 2: office router private IP"
  value       = one(module.connectivity[*].onprem_private_ip)
}

output "site_bucket" {
  description = "Week 3: private S3 bucket behind CloudFront"
  value       = try(module.edge[0].site_bucket_name, null)
}

output "alb_health_check_id" {
  description = "Week 3: Route 53 health check on the ALB"
  value       = try(aws_route53_health_check.alb[0].id, null)
}

output "tgw_id" {
  description = "Week 2: Transit Gateway"
  value       = one(module.connectivity[*].tgw_id)
}

output "vpn_connection_id" {
  description = "Week 2: download the strongSwan config for this VPN in the console"
  value       = one(module.connectivity[*].vpn_connection_id)
}

output "strongswan_public_ip" {
  description = "Week 2: customer gateway IP"
  value       = one(module.connectivity[*].strongswan_public_ip)
}

output "strongswan_instance_id" {
  description = "Week 2: Session Manager target for the office router"
  value       = one(module.connectivity[*].onprem_instance_id)
}

output "vpn_tunnel1_address" {
  description = "Week 2: AWS tunnel 1 outside IP (right= in ipsec.conf)"
  value       = one(module.connectivity[*].vpn_tunnel1_address)
}

output "vpn_tunnel1_psk" {
  description = "Week 2: tunnel 1 pre-shared key. Read with: terraform output -raw vpn_tunnel1_psk (never paste it anywhere)"
  value       = one(module.connectivity[*].vpn_tunnel1_psk)
  sensitive   = true
}

output "privatelink_dns" {
  description = "Week 2: curl this from the hub web server"
  value       = try(aws_vpc_endpoint.consumer[0].dns_entry[0].dns_name, null)
}

output "app_url" {
  description = "Week 3: the web app through CloudFront + WAF (the ALB only accepts CloudFront)"
  value       = try("https://${module.edge[0].app_domain}/", null)
}

output "cloudfront_url" {
  description = "Week 3: the protected static site"
  value       = try("https://${module.edge[0].cloudfront_domain}/index.html", null)
}

output "victim_instance_id" {
  description = "Week 4: the compromised instance"
  value       = try(aws_instance.victim[0].id, null)
}

output "victim_private_ip" {
  description = "Week 4: use it in the Athena timeline query"
  value       = try(aws_instance.victim[0].private_ip, null)
}

output "client_vpn_endpoint_id" {
  description = "Week 2 lab: download the client configuration for this endpoint"
  value       = try(aws_ec2_client_vpn_endpoint.this[0].id, null)
}

output "network_alerts_topic" {
  description = "Week 4: SNS topic for network alarms (confirm the email subscription)"
  value       = module.monitoring.network_alerts_topic_arn
}

# ---------- Week 4 security layers (D9-D15), read by scripts/demo-tests.sh ----------
output "data_route_table_id" {
  description = "D9: route table of the isolated data subnets (local route only)"
  value       = module.vpc.data_route_table_id
}

output "guardduty_detector_id" {
  description = "D10: GuardDuty detector (null when enable_detection = false)"
  value       = one(aws_guardduty_detector.this[*].id)
}

output "findings_topic_arn" {
  description = "D13: SNS topic for GuardDuty findings"
  value       = one(aws_sns_topic.findings[*].arn)
}

output "dns_firewall_rule_group_id" {
  description = "D12: DNS Firewall rule group"
  value       = aws_route53_resolver_firewall_rule_group.this.id
}

output "ssm_session_log_group" {
  description = "D14: CloudWatch log group with every Session Manager session"
  value       = aws_cloudwatch_log_group.ssm_sessions.name
}

output "cloudfront_distribution_id" {
  description = "Site distribution ID (for cache invalidation after a website update)"
  value       = try(module.edge[0].cloudfront_distribution_id, null)
}
