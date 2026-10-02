output "spoke_vpc_ids" {
  description = "Spoke VPC IDs keyed a / b"
  value       = { for k, v in aws_vpc.spoke : k => v.id }
}

output "spoke_subnet_ids" {
  description = "Spoke subnet IDs keyed a / b"
  value       = { for k, v in aws_subnet.spoke : k => v.id }
}

output "spoke_cidrs" {
  description = "Spoke CIDRs keyed a / b"
  value       = var.spokes
}

output "onprem_vpc_id" {
  description = "Simulated on-prem VPC"
  value       = one(aws_vpc.onprem[*].id)
}

output "onprem_instance_id" {
  description = "strongSwan router instance"
  value       = one(aws_instance.strongswan[*].id)
}

output "strongswan_public_ip" {
  description = "Customer gateway public IP"
  value       = one(aws_eip.strongswan[*].public_ip)
}

output "tgw_id" {
  description = "Transit Gateway ID"
  value       = aws_ec2_transit_gateway.this.id
}

output "vpn_connection_id" {
  description = "Use it to download the strongSwan config in the console"
  value       = one(aws_vpn_connection.this[*].id)
}

output "vpn_tunnel1_address" {
  description = "AWS side outside IP of tunnel 1"
  value       = one(aws_vpn_connection.this[*].tunnel1_address)
}

output "vpn_tunnel1_psk" {
  description = "Pre-shared key tunnel 1. Read with: terraform output -raw vpn_tunnel1_psk"
  value       = one(aws_vpn_connection.this[*].tunnel1_preshared_key)
  sensitive   = true
}
