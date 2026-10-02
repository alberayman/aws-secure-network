variable "name" {
  description = "Name prefix for every resource, e.g. secnet"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the hub VPC"
  type        = string
}

variable "azs" {
  description = "Availability Zones to use, one subnet of each type per AZ"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "One CIDR per AZ for the public subnets (ALB, NAT)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "One CIDR per AZ for the private subnets (EC2, RDS, TGW attachment)"
  type        = list(string)
}

variable "extra_allowed_cidrs" {
  description = "Other networks allowed into the private NACL (spokes, on-prem). Week 2."
  type        = list(string)
  default     = []
}

variable "enable_nat" {
  description = "Create the NAT gateway (about $1.15/day). Set false overnight to save money."
  type        = bool
  default     = true
}
