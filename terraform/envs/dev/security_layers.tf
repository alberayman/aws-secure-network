# Week 4 design review (docs/week4/README.md): extra security layers D10-D15.
# D9 (isolated data subnets) lives in modules/vpc + modules/compute.

locals {
  detect = var.enable_detection
  # VPCs protected by the DNS Firewall: the hub always, the spokes when Week 2 is on
  dns_fw_vpcs = merge(
    { hub = module.vpc.vpc_id },
    local.hybrid ? { spoke_a = module.connectivity[0].spoke_vpc_ids["a"], spoke_b = module.connectivity[0].spoke_vpc_ids["b"] } : {}
  )
}

# ---------------- D10: GuardDuty ----------------
# Foundational sources (CloudTrail, VPC Flow Logs, DNS) are always analysed. Paid add-ons off
# so the cost stays predictable after the 30-day trial.
resource "aws_guardduty_detector" "this" {
  count                        = local.detect ? 1 : 0
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  tags                         = { Name = "${var.name}-guardduty" }
}

resource "aws_guardduty_detector_feature" "off" {
  for_each    = local.detect ? toset(["S3_DATA_EVENTS", "EBS_MALWARE_PROTECTION", "RDS_LOGIN_EVENTS", "LAMBDA_NETWORK_LOGS"]) : toset([])
  detector_id = aws_guardduty_detector.this[0].id
  name        = each.value
  status      = "DISABLED"

  # AWS attaches a sub-setting (RDS_DATA_RISK) to RDS_LOGIN_EVENTS by itself. Our provider
  # version (5.x) cannot declare it (validation error), so ignore it to stop a replace on every
  # plan. Revisit when the provider supports it.
  lifecycle {
    ignore_changes = [additional_configuration]
  }
}

# ---------------- D13: findings -> EventBridge -> SNS email ----------------
resource "aws_sns_topic" "findings" {
  count = local.detect ? 1 : 0
  name  = "${var.name}-security-findings"
}

resource "aws_sns_topic_subscription" "findings_email" {
  count     = local.detect ? 1 : 0
  topic_arn = aws_sns_topic.findings[0].arn
  protocol  = "email"
  endpoint  = var.alert_email # confirm the subscription email!
}

resource "aws_cloudwatch_event_rule" "guardduty" {
  count       = local.detect ? 1 : 0
  name        = "${var.name}-guardduty-findings"
  description = "GuardDuty findings, severity medium and above"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail        = { severity = [{ numeric = [">=", 4] }] }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  count = local.detect ? 1 : 0
  rule  = aws_cloudwatch_event_rule.guardduty[0].name
  arn   = aws_sns_topic.findings[0].arn
  input_transformer {
    input_paths = {
      sev   = "$.detail.severity"
      type  = "$.detail.type"
      title = "$.detail.title"
      res   = "$.detail.resource.resourceType"
    }
    input_template = "\"GuardDuty finding (severity <sev>): <type> on <res>. <title>\""
  }
}

resource "aws_sns_topic_policy" "findings" {
  count = local.detect ? 1 : 0
  arn   = aws_sns_topic.findings[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridge"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.findings[0].arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.guardduty[0].arn } }
    }]
  })
}

# ---------------- D11: AWS Config rules (continuous T7) ----------------
# Records security groups only: enough for the two rules and keeps the cost at cents,
# even with the nightly make sleep / rebuild churn.
resource "aws_iam_role" "config" {
  count = local.detect ? 1 : 0
  name  = "${var.name}-config-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "config.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  count      = local.detect ? 1 : 0
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_s3" {
  count = local.detect ? 1 : 0
  name  = "deliver-to-logs-bucket"
  role  = aws_iam_role.config[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "s3:GetBucketAcl", Resource = module.monitoring.logs_bucket_arn },
      { Effect = "Allow", Action = "s3:PutObject", Resource = "${module.monitoring.logs_bucket_arn}/config/*" }
    ]
  })
}

resource "aws_config_configuration_recorder" "this" {
  count    = local.detect ? 1 : 0
  name     = "${var.name}-recorder"
  role_arn = aws_iam_role.config[0].arn
  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types                = ["AWS::EC2::SecurityGroup"]
    recording_strategy {
      use_only = "INCLUSION_BY_RESOURCE_TYPES"
    }
  }
}

resource "aws_config_delivery_channel" "this" {
  count          = local.detect ? 1 : 0
  name           = "${var.name}-delivery"
  s3_bucket_name = module.monitoring.logs_bucket_name
  s3_key_prefix  = "config"
  depends_on     = [aws_config_configuration_recorder.this, aws_iam_role_policy.config_s3]
}

resource "aws_config_configuration_recorder_status" "this" {
  count      = local.detect ? 1 : 0
  name       = aws_config_configuration_recorder.this[0].name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}

resource "aws_config_config_rule" "default_sg_closed" {
  count = local.detect ? 1 : 0
  name  = "${var.name}-default-sg-closed"
  source {
    owner             = "AWS"
    source_identifier = "VPC_DEFAULT_SECURITY_GROUP_CLOSED"
  }
  depends_on = [aws_config_configuration_recorder_status.this]
}

resource "aws_config_config_rule" "no_ssh_from_internet" {
  count = local.detect ? 1 : 0
  name  = "${var.name}-restricted-ssh"
  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
  depends_on = [aws_config_configuration_recorder_status.this]
}

# ---------------- D13: Security Hub (one dashboard) ----------------
resource "aws_securityhub_account" "this" {
  count                    = local.detect ? 1 : 0
  enable_default_standards = false # we pick the standard below (cost control)
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  count         = local.detect ? 1 : 0
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# ---------------- D15: IAM Access Analyzer ----------------
resource "aws_accessanalyzer_analyzer" "this" {
  count         = local.detect ? 1 : 0
  analyzer_name = "${var.name}-access-analyzer"
  type          = "ACCOUNT"
}

# ---------------- D12: Route 53 Resolver DNS Firewall ----------------
# Blocks malware / botnet C2 domains even though the NAT allows any outbound connection.
# Our own list blocks immediately; the AWS managed lists start in ALERT (false-positive check).
resource "aws_route53_resolver_firewall_domain_list" "blocklist" {
  name    = "${var.name}-blocklist"
  domains = ["c2.evil-demo.example."] # stand-in for a known-bad domain (demo test T45)
}

resource "aws_route53_resolver_firewall_rule_group" "this" {
  name = "${var.name}-dns-firewall"
}

resource "aws_route53_resolver_firewall_rule" "blocklist" {
  name                    = "block-own-list"
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.this.id
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.blocklist.id
  priority                = 100
  action                  = "BLOCK"
  block_response          = "OVERRIDE"
  block_override_dns_type = "CNAME"
  block_override_domain   = "dns-firewall-blocked.secnet.internal."
  block_override_ttl      = 60
}

resource "aws_route53_resolver_firewall_rule" "managed" {
  for_each                = { for i, id in var.dns_firewall_managed_list_ids : tostring(i) => id }
  name                    = "aws-managed-${each.key}"
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.this.id
  firewall_domain_list_id = each.value
  priority                = 200 + tonumber(each.key)
  action                  = var.dns_firewall_managed_action
  block_response          = var.dns_firewall_managed_action == "BLOCK" ? "NXDOMAIN" : null
}

resource "aws_route53_resolver_firewall_rule_group_association" "this" {
  for_each               = local.dns_fw_vpcs
  name                   = "${var.name}-dnsfw-${each.key}"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.this.id
  vpc_id                 = each.value
  priority               = 101
}

# ---------------- D14: Session Manager logging ----------------
# Every interactive shell (who, when, every command) is streamed to CloudWatch Logs: IR evidence.
resource "aws_cloudwatch_log_group" "ssm_sessions" {
  name              = "/${var.name}/ssm-sessions"
  retention_in_days = 30
}

resource "aws_ssm_document" "session_prefs" {
  name            = "SSM-SessionManagerRunShell" # the name Session Manager reads its preferences from
  document_type   = "Session"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences: log every session to CloudWatch"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = false
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.ssm_sessions.name
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = true
      idleSessionTimeout          = "20"
      runAsEnabled                = false
      runAsDefaultUser            = ""
      shellProfile                = { linux = "", windows = "" }
    }
  })
}

# The instance role needs to write the session stream
resource "aws_iam_role_policy" "session_logging" {
  count = var.enable_compute ? 1 : 0
  name  = "ssm-session-logging"
  role  = one(module.compute[*].ec2_role_name)
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.ssm_sessions.arn}:*" },
      { Effect = "Allow", Action = ["logs:DescribeLogGroups", "logs:DescribeLogStreams"], Resource = "*" }
    ]
  })
}

# ---------------- D11 follow-up: default VPC's default security group ----------------
# Found by the Config rule secnet-default-sg-closed (NON_COMPLIANT, 2026-11-21): the account's
# default VPC (outside the project) still had AWS's built-in allow-self / allow-all-egress rules.
# Managing it here with no rule blocks strips them and keeps it closed (CIS 5.4). Nothing uses it.
data "aws_vpc" "default" {
  default = true
}

resource "aws_default_security_group" "default_vpc" {
  vpc_id = data.aws_vpc.default.id
  tags   = { Name = "default-vpc-default-sg-do-not-use", ManagedBy = "terraform-secnet" }
}
