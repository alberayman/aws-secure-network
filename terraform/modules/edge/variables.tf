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
