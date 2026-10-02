variable "name" {
  description = "Name prefix"
  type        = string
}

variable "az" {
  description = "AZ for the single-subnet spoke and on-prem VPCs (same as hub subnet 1)"
  type        = string
}

variable "hub_vpc_id" {
  description = "Hub VPC ID"
  type        = string
}

variable "hub_vpc_cidr" {
  description = "Hub VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "hub_private_subnet_ids" {
  description = "Hub private subnets for the TGW attachment (one per AZ)"
  type        = list(string)
}

variable "hub_private_route_table_id" {
  description = "Hub private route table to receive spoke/on-prem routes"
  type        = string
}

variable "instance_profile_name" {
  description = "SSM instance profile for the strongSwan router"
  type        = string
}

variable "spokes" {
  description = "Spoke VPCs: a = peering, b = Transit Gateway"
  type        = map(string)
  default     = { a = "10.1.0.0/16", b = "10.2.0.0/16" }
}

variable "onprem_cidr" {
  description = "Simulated on-premises network"
  type        = string
  default     = "192.168.0.0/16"
}

variable "enable_vpn" {
  description = "Build the simulated office + Site-to-Site VPN (about $2.50/day)"
  type        = bool
  default     = true
}
