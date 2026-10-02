# VPC Flow Logs (metadata of every accepted/rejected flow) to S3, default format,
# 10-minute aggregation. Prefix per VPC: flowlogs/<name>/AWSLogs/...
resource "aws_flow_log" "this" {
  for_each                 = var.vpc_ids
  vpc_id                   = each.value
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = "${aws_s3_bucket.logs.arn}/flowlogs/${each.key}/"
  max_aggregation_interval = 600
  tags                     = { Name = "${var.name}-flowlog-${each.key}" }
  depends_on               = [aws_s3_bucket_policy.logs]
}
