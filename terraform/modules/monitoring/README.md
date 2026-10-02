# monitoring module

**Owner:** Member 5 – Ahmed (Logging and incident response) · **Weeks:** 1 (CloudTrail, bucket) · 2 (Flow Logs) · 4 (Athena)

Private, versioned, encrypted log bucket (TLS-only policy, 30-day expiry), multi-region **CloudTrail** with
log-file validation, **VPC Flow Logs** for every VPC passed in `vpc_ids`, an **Athena** workgroup + database
and six saved queries (table DDL + five detections). `cloudwatch.tf` adds a 1-minute copy of the
flows for `cloudwatch_flowlog_vpc_ids` in CloudWatch Logs, metric filters for internal rejected flows and SSH attempts,
two alarms to an SNS email topic, two Logs Insights saved queries and a `secnet-network` dashboard.

Inputs: `name`, `vpc_ids` (map), `log_retention_days`, `cloudwatch_flowlog_vpc_ids` (map), `alert_email`, `reject_alarm_threshold`.
Outputs: `logs_bucket_name`, `logs_bucket_arn`, `trail_arn`, `athena_workgroup`, `athena_database`, `network_alerts_topic_arn`.

**Test:** CloudTrail event history shows your actions · `.log.gz` under `flowlogs/<vpc>/AWSLogs/` ·
Athena saved query `01-create-flow-logs-table` runs, then `10-top-rejected-sources` returns rows.
**Cost:** first CloudTrail management trail is free; S3 + Athena pennies ($5 per TB scanned).
