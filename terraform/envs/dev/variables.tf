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
