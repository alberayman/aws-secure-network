# Edge: private S3 origin -> CloudFront (OAC, HTTPS) -> WAF web ACL (us-east-1) + Shield Standard.

data "aws_caller_identity" "current" {}

# ---------- Private S3 origin ----------
resource "aws_s3_bucket" "site" {
  bucket        = "${var.name}-site-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # lab only
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------- WAF web ACL (CLOUDFRONT scope must be created in us-east-1) ----------
resource "aws_wafv2_web_acl" "site" {
  provider = aws.us_east_1
  name     = "${var.name}-cf-acl"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = {
      common   = { name = "AWSManagedRulesCommonRuleSet", priority = 1 }
      badinput = { name = "AWSManagedRulesKnownBadInputsRuleSet", priority = 2 }
      sqli     = { name = "AWSManagedRulesSQLiRuleSet", priority = 3 }
      iprep    = { name = "AWSManagedRulesAmazonIpReputationList", priority = 4 }
    }
    content {
      name     = rule.key
      priority = rule.value.priority
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  rule {
    name     = "rate-limit"
    priority = 10
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "geo-block"
    priority = 20
    action {
      block {}
    }
    statement {
      geo_match_statement {
        country_codes = var.blocked_countries
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "geo-block"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-cf-acl"
    sampled_requests_enabled   = true
  }
}

# ---------- CloudFront ----------
resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "${var.name} static site"
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # cheapest: NA + Europe edges
  web_acl_id          = aws_wafv2_web_acl.site.arn
  http_version        = "http2and3"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "s3-site"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03" # Managed-SecurityHeadersPolicy
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Default *.cloudfront.net certificate. Production: a custom domain with an ACM cert in us-east-1
    # and minimum_protocol_version = "TLSv1.2_2021".
    cloudfront_default_certificate = true
  }
}

# Only this distribution may read the bucket (OAC + SourceArn condition)
resource "aws_s3_bucket_policy" "site" {
  bucket     = aws_s3_bucket.site.id
  depends_on = [aws_s3_bucket_public_access_block.site]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site.arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.site.arn } }
    }]
  })
}
