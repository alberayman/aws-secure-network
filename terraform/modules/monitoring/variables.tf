variable "name" {
  description = "Name prefix"
  type        = string
}

variable "vpc_ids" {
  description = "VPCs to enable Flow Logs on: name => VPC ID, e.g. { hub = \"vpc-...\" }"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Days before log objects expire in S3"
  type        = number
  default     = 30
}
