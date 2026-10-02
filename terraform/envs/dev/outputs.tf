output "alb_url" {
  description = "Week 1: open in a browser"
  value       = "http://${module.compute.alb_dns_name}"
}

output "web_instance_id" {
  description = "Week 1: Session Manager target"
  value       = module.compute.web_instance_id
}

output "web_private_ip" {
  description = "Week 1/2: ping target for the test matrix"
  value       = module.compute.web_private_ip
}

output "db_endpoint" {
  description = "Week 1: RDS hostname"
  value       = module.compute.db_endpoint
}

output "db_secret_arn" {
  description = "Week 1: Secrets Manager secret with the DB password"
  value       = module.compute.db_secret_arn
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

output "privatelink_dns" {
  description = "Week 2: curl this from the hub web server"
  value       = try(aws_vpc_endpoint.consumer[0].dns_entry[0].dns_name, null)
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
