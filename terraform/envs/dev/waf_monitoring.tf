# Week 3 (Member 5): WAF logs to CloudWatch, an SNS email topic and a BlockedRequests alarm.
# All in us-east-1 because the web ACL has CLOUDFRONT scope.

resource "aws_cloudwatch_log_group" "waf" {
  count             = var.enable_edge ? 1 : 0
  provider          = aws.us_east_1
  name              = "aws-waf-logs-${var.name}" # the name MUST start with aws-waf-logs-
  retention_in_days = 14
}

resource "aws_cloudwatch_log_resource_policy" "waf" {
  count       = var.enable_edge ? 1 : 0
  provider    = aws.us_east_1
  policy_name = "${var.name}-waf-logs"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "WAFLogs"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.waf[0].arn}:*"
    }]
  })
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count                   = var.enable_edge ? 1 : 0
  provider                = aws.us_east_1
  resource_arn            = module.edge[0].web_acl_arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]
  depends_on              = [aws_cloudwatch_log_resource_policy.waf]
}

resource "aws_sns_topic" "alerts" {
  count    = var.enable_edge ? 1 : 0
  provider = aws.us_east_1
  name     = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.enable_edge ? 1 : 0
  provider  = aws.us_east_1
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email # click the confirmation link in the email!
}

resource "aws_cloudwatch_metric_alarm" "waf_blocked" {
  count               = var.enable_edge ? 1 : 0
  provider            = aws.us_east_1
  alarm_name          = "${var.name}-waf-blocked"
  alarm_description   = "More than 5 requests blocked by WAF in 5 minutes"
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  # CloudFront-scope metrics have no Region dimension. If the alarm stays in
  # "Insufficient data", copy the exact dimensions shown in CloudWatch > Metrics > WAFV2.
  dimensions = {
    WebACL = module.edge[0].web_acl_name
    Rule   = "ALL"
  }
}
