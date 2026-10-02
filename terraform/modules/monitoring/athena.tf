# Saved queries. Run "01-create-flow-logs-table" once in the Athena console (workgroup secnet),
# then the detection queries work.

resource "aws_athena_database" "this" {
  name          = var.name
  bucket        = aws_s3_bucket.logs.id
  force_destroy = true
  encryption_configuration {
    encryption_option = "SSE_S3"
  }
}

locals {
  queries = {
    "01-create-flow-logs-table" = <<-SQL
      CREATE EXTERNAL TABLE IF NOT EXISTS vpc_flow_logs (
        version int, account_id string, interface_id string,
        srcaddr string, dstaddr string, srcport int, dstport int,
        protocol bigint, packets bigint, bytes bigint,
        `start` bigint, `end` bigint, action string, log_status string
      )
      ROW FORMAT DELIMITED FIELDS TERMINATED BY ' '
      LOCATION 's3://${aws_s3_bucket.logs.id}/flowlogs/'
      TBLPROPERTIES ('skip.header.line.count'='1');
    SQL

    "10-top-rejected-sources" = <<-SQL
      SELECT srcaddr, dstaddr, dstport, count(*) AS rejects
      FROM vpc_flow_logs WHERE action = 'REJECT'
      GROUP BY srcaddr, dstaddr, dstport ORDER BY rejects DESC LIMIT 20;
    SQL

    "11-port-22-attempts" = <<-SQL
      SELECT srcaddr, dstaddr, action, count(*) AS hits
      FROM vpc_flow_logs WHERE dstport = 22
      GROUP BY srcaddr, dstaddr, action ORDER BY hits DESC;
    SQL

    "12-port-scan-pattern" = <<-SQL
      SELECT srcaddr, dstaddr, count(DISTINCT dstport) AS ports
      FROM vpc_flow_logs WHERE action = 'REJECT'
      GROUP BY srcaddr, dstaddr HAVING count(DISTINCT dstport) > 10 ORDER BY ports DESC;
    SQL

    "13-unusual-outbound" = <<-SQL
      SELECT srcaddr, dstaddr, dstport, sum(bytes) AS total_bytes
      FROM vpc_flow_logs
      WHERE srcaddr LIKE '10.0.%' AND dstaddr NOT LIKE '10.%'
        AND dstport NOT IN (80, 443, 53, 123)
      GROUP BY srcaddr, dstaddr, dstport ORDER BY total_bytes DESC LIMIT 20;
    SQL

    "14-host-timeline" = <<-SQL
      -- replace 10.0.11.X with the victim private IP
      SELECT from_unixtime("start") AS time, srcaddr, dstaddr, dstport, action
      FROM vpc_flow_logs WHERE srcaddr = '10.0.11.X' OR dstaddr = '10.0.11.X'
      ORDER BY "start";
    SQL
  }
}

resource "aws_athena_named_query" "this" {
  for_each  = local.queries
  name      = each.key
  workgroup = aws_athena_workgroup.this.id
  database  = aws_athena_database.this.name
  query     = each.value
}
