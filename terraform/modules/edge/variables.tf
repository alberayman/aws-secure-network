variable "name" {
  description = "Name prefix"
  type        = string
}

variable "rate_limit" {
  description = "Max requests per IP per 5 minutes before WAF blocks"
  type        = number
  default     = 100
}

variable "blocked_countries" {
  description = "ISO country codes to geo-block (change for the test, then set back)"
  type        = list(string)
  default     = ["KP"]
}

variable "enable_app" {
  description = "Put the web app (ALB) behind a second CloudFront distribution with the same WAF"
  type        = bool
  default     = false
}

variable "alb_dns_name" {
  description = "ALB DNS name (app origin)"
  type        = string
  default     = null
}

variable "origin_verify_secret" {
  description = "Secret header value sent to the ALB origin"
  type        = string
  default     = null
  sensitive   = true
}
