output "vpc_id" {
  description = "Hub VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Hub VPC CIDR"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EC2, RDS, endpoints)"
  value       = aws_subnet.private[*].id
}

output "private_route_table_id" {
  description = "Private route table; the connectivity module adds spoke/on-prem routes here"
  value       = aws_route_table.private.id
}

output "nat_gateway_id" {
  description = "NAT gateway ID (expensive when idle)"
  value       = one(aws_nat_gateway.this[*].id)
}

output "tgw_subnet_ids" {
  description = "Week 2: dedicated /28 subnets for the Transit Gateway attachment (empty when hybrid is off)"
  value       = aws_subnet.tgw[*].id
}
