# Week 1 (Member 6): cost guardrail. Email alerts at 25/50/80% actual and 100% forecast.
resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Track gross usage: with the defaults, promotional credits and refunds are netted out, so
  # actual cost shows $0 and the alerts never fire while credits last (found 2026-10-11).
  cost_types {
    include_credit = false
    include_refund = false
  }

  dynamic "notification" {
    for_each = [25, 50, 80]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
