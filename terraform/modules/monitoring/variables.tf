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

variable "cloudwatch_flowlog_vpc_ids" {
  description = "VPCs whose Flow Logs ALSO go to CloudWatch Logs for near-real-time alarms (keep small: ingestion is billed per GB)"
  type        = map(string)
  default     = {}
}

variable "alert_email" {
  description = "Email subscribed to the network alarm SNS topic (empty = no subscription)"
  type        = string
  default     = ""
}

variable "reject_alarm_threshold" {
  description = "Rejected flows in 5 minutes before the alarm fires"
  type        = number
  default     = 25
}
