# Week 3 (Member 2): the project website CloudFront serves from the private bucket.
# Source files live in /website at the repo root. etag = MD5, so Terraform re-uploads a file
# only when it changes. After an update, invalidate the CloudFront cache (see docs/week3/README.md).

locals {
  site_dir = "${path.module}/../../../website"
  site_files = {
    "index.html"        = "text/html; charset=utf-8"
    "architecture.png"  = "image/png"
    "traffic-flows.png" = "image/png"
  }
}

resource "aws_s3_object" "site" {
  for_each     = var.enable_edge ? local.site_files : {}
  bucket       = module.edge[0].site_bucket_name
  key          = each.key
  source       = "${local.site_dir}/${each.key}"
  etag         = filemd5("${local.site_dir}/${each.key}")
  content_type = each.value
}

# The old single-object resource became the "index.html" entry above (no re-create).
moved {
  from = aws_s3_object.index[0]
  to   = aws_s3_object.site["index.html"]
}
