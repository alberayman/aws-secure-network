variable "name" {
  description = "Name prefix"
  type        = string
}

variable "vpc_id" {
  description = "Hub VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for EC2 and RDS"
  type        = list(string)
}

variable "internal_cidrs" {
  description = "Networks allowed to ping the web instance (Week 2 tests)"
  type        = list(string)
  default     = ["10.0.0.0/8", "192.168.0.0/16"]
}

variable "instance_type" {
  description = "EC2 size (free-tier eligible)"
  type        = string
  default     = "t3.micro"
}
