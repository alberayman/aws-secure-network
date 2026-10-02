# Week 4 (Member 5): near-real-time network detection in CloudWatch.
# S3 Flow Logs (flowlogs.tf) are the cheap long-term store queried with Athena;
# CloudWatch gets a 1-minute copy of the hub's flows so metric filters can raise alarms in minutes.

resource "aws_cloudwatch_log_group" "flowlogs" {
  for_each          = var.cloudwatch_flowlog_vpc_ids
  name              = "/${var.name}/flowlogs/${each.key}"
  retention_in_days = 14
}

data "aws_iam_policy_document" "flowlogs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "flowlogs" {
  count              = length(var.cloudwatch_flowlog_vpc_ids) > 0 ? 1 : 0
  name               = "${var.name}-flowlogs-to-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.flowlogs_assume.json
}

# Least privilege: write only to our flow-log groups
resource "aws_iam_role_policy" "flowlogs" {
  count = length(var.cloudwatch_flowlog_vpc_ids) > 0 ? 1 : 0
  name  = "write-flowlog-groups"
  role  = aws_iam_role.flowlogs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = [for g in aws_cloudwatch_log_group.flowlogs : "${g.arn}:*"]
    }]
  })
}

resource "aws_flow_log" "cloudwatch" {
  for_each                 = var.cloudwatch_flowlog_vpc_ids
  vpc_id                   = each.value
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flowlogs[each.key].arn
  iam_role_arn             = aws_iam_role.flowlogs[0].arn
  max_aggregation_interval = 60
  tags                     = { Name = "${var.name}-flowlog-cw-${each.key}" }
}

# Default flow-log format, space separated: the pattern names each field.
# Both filters only count INTERNAL sources (srcaddr 10.*): the ALB and NAT public IPs are scanned
# by the internet all day, and that background noise would make the alarms useless.

resource "aws_cloudwatch_log_metric_filter" "rejects" {
  for_each       = var.cloudwatch_flowlog_vpc_ids
  name           = "${var.name}-${each.key}-rejected-flows"
  log_group_name = aws_cloudwatch_log_group.flowlogs[each.key].name
  pattern        = "[version, account_id, interface_id, srcaddr = \"10.*\", dstaddr, srcport, dstport, protocol, packets, bytes, start, end, action = \"REJECT\", log_status]"
  metric_transformation {
    name          = "RejectedFlows"
    namespace     = "${var.name}/Network"
    value         = "1"
    default_value = "0"
    dimensions    = { VPC = each.key }
  }
}

resource "aws_cloudwatch_log_metric_filter" "ssh" {
  for_each       = var.cloudwatch_flowlog_vpc_ids
  name           = "${var.name}-${each.key}-ssh-attempts"
  log_group_name = aws_cloudwatch_log_group.flowlogs[each.key].name
  pattern        = "[version, account_id, interface_id, srcaddr = \"10.*\", dstaddr, srcport, dstport = 22, protocol, packets, bytes, start, end, action, log_status]"
  metric_transformation {
    name          = "SSHAttempts"
    namespace     = "${var.name}/Network"
    value         = "1"
    default_value = "0"
    dimensions    = { VPC = each.key }
  }
}

resource "aws_sns_topic" "network_alerts" {
  name = "${var.name}-network-alerts"
}

resource "aws_sns_topic_subscription" "network_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.network_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "rejects" {
  for_each            = var.cloudwatch_flowlog_vpc_ids
  alarm_name          = "${var.name}-${each.key}-rejected-flows-spike"
  alarm_description   = "Possible internal scan: more than ${var.reject_alarm_threshold} rejected flows from 10.x sources in 5 minutes in ${each.key}"
  namespace           = "${var.name}/Network"
  metric_name         = "RejectedFlows"
  dimensions          = { VPC = each.key }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.reject_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.network_alerts.arn]
  ok_actions          = [aws_sns_topic.network_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "ssh" {
  for_each            = var.cloudwatch_flowlog_vpc_ids
  alarm_name          = "${var.name}-${each.key}-ssh-attempt"
  alarm_description   = "Internal host tried SSH (port 22): SSH does not exist in this design"
  namespace           = "${var.name}/Network"
  metric_name         = "SSHAttempts"
  dimensions          = { VPC = each.key }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.network_alerts.arn]
}

# Saved CloudWatch Logs Insights queries (CloudWatch > Logs Insights > Saved queries)
resource "aws_cloudwatch_query_definition" "top_rejects" {
  count           = length(var.cloudwatch_flowlog_vpc_ids) > 0 ? 1 : 0
  name            = "${var.name}/top-rejected-sources"
  log_group_names = [for g in aws_cloudwatch_log_group.flowlogs : g.name]
  query_string    = <<-EOT
    fields @timestamp, @message
    | parse @message "* * * * * * * * * * * * * *" as version, account, eni, src, dst, srcport, dstport, proto, packets, bytes, start, end, action, status
    | filter action = "REJECT"
    | stats count(*) as rejects by src, dst, dstport
    | sort rejects desc
    | limit 20
  EOT
}

resource "aws_cloudwatch_query_definition" "port_scan" {
  count           = length(var.cloudwatch_flowlog_vpc_ids) > 0 ? 1 : 0
  name            = "${var.name}/port-scan-pattern"
  log_group_names = [for g in aws_cloudwatch_log_group.flowlogs : g.name]
  query_string    = <<-EOT
    fields @message
    | parse @message "* * * * * * * * * * * * * *" as version, account, eni, src, dst, srcport, dstport, proto, packets, bytes, start, end, action, status
    | filter action = "REJECT"
    | stats count_distinct(dstport) as ports by src, dst
    | filter ports > 10
    | sort ports desc
  EOT
}

# A one-glance network dashboard for the Week 4 demo
resource "aws_cloudwatch_dashboard" "network" {
  count          = length(var.cloudwatch_flowlog_vpc_ids) > 0 ? 1 : 0
  dashboard_name = "${var.name}-network"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "Rejected flows and SSH attempts (per 5 min)"
          region = local.region
          stat   = "Sum"
          period = 300
          view   = "timeSeries"
          metrics = concat(
            [for k, _ in var.cloudwatch_flowlog_vpc_ids : ["${var.name}/Network", "RejectedFlows", "VPC", k]],
            [for k, _ in var.cloudwatch_flowlog_vpc_ids : ["${var.name}/Network", "SSHAttempts", "VPC", k]]
          )
        }
      },
      {
        type = "alarm", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Network alarms"
          alarms = concat([for a in aws_cloudwatch_metric_alarm.rejects : a.arn], [for a in aws_cloudwatch_metric_alarm.ssh : a.arn])
        }
      }
    ]
  })
}
