variable "region" {
  description = "Main region for the project"
  type        = string
  default     = "eu-west-1"
}

variable "name" {
  description = "Name prefix for every resource"
  type        = string
  default     = "secnet"
}

variable "alert_email" {
  description = "Email for budget and WAF alarm notifications (confirm the SNS email!)"
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget; alerts at 25%, 50%, 80% and forecast 100%"
  type        = number
  default     = 50
}

# ---------- Week switches: turn a week on, plan, apply; turn it off to destroy it ----------
variable "enable_nat" {
  description = "Week 1+. NAT gateway for private hosts (about $1.15/day). false overnight."
  type        = bool
  default     = true
}

variable "enable_hybrid" {
  description = "Week 2. Spokes, peering, Transit Gateway, endpoints, PrivateLink, spoke tests"
  type        = bool
  default     = false
}

variable "enable_vpn" {
  description = "Week 2. Simulated office + Site-to-Site VPN (needs enable_hybrid)"
  type        = bool
  default     = false
}

variable "enable_edge" {
  description = "Week 3. CloudFront, S3 site, WAF, Route 53, WAF logging and alarm"
  type        = bool
  default     = false
}

variable "enable_ir" {
  description = "Week 4. Victim instance, evidence snapshot, isolation security group"
  type        = bool
  default     = false
}

variable "isolate_victim" {
  description = "Week 4 containment drill: true swaps the victim onto the quarantine SG"
  type        = bool
  default     = false
}

variable "enable_mirroring" {
  description = "Week 4. Traffic Mirroring target + session on the victim (needs enable_ir)"
  type        = bool
  default     = false
}

variable "waf_blocked_countries" {
  description = "Countries the WAF geo rule blocks (change for the test, then set back)"
  type        = list(string)
  default     = ["KP"]
}

# ---------- Week 2 optional lab: Client VPN (remote users) ----------
variable "enable_client_vpn" {
  description = "Week 2 lab. AWS Client VPN endpoint into the hub (~$0.10/h + $0.05/h per connection)"
  type        = bool
  default     = false
}

variable "client_vpn_server_cert_arn" {
  description = "ACM ARN of the imported Client VPN SERVER certificate (Guide 2.7)"
  type        = string
  default     = ""
}

variable "client_vpn_client_ca_arn" {
  description = "ACM ARN of the imported CLIENT certificate / CA used for mutual TLS (Guide 2.7)"
  type        = string
  default     = ""
}

variable "client_vpn_cidr" {
  description = "Addresses handed to VPN users. Must not overlap any VPC or the office (min /22)"
  type        = string
  default     = "172.16.0.0/22"
}

# ---------- Week 4: CloudWatch network detection ----------
variable "reject_alarm_threshold" {
  description = "Rejected flows in 5 minutes (hub VPC) before the network alarm fires"
  type        = number
  default     = 25
}
