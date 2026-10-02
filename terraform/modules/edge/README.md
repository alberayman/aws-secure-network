# edge module

**Owner:** Member 4 (Edge and access security) · **Week:** 3

Private, encrypted, versioned S3 bucket → CloudFront with **Origin Access Control** and HTTPS redirect
→ **AWS WAF** web ACL (4 AWS managed rule groups + rate limit + geo block) → Shield Standard (automatic).

Needs two providers: default (eu-west-1) and `aws.us_east_1` (CLOUDFRONT-scope WAF lives in us-east-1).

Inputs: `name`, `rate_limit` (default 100 per 5 min per IP), `blocked_countries` (default `["KP"]`).
Outputs: `site_bucket_name`, `cloudfront_domain`, `cloudfront_distribution_id`, `web_acl_arn`, `web_acl_name`.

**Test:** direct S3 URL → 403 AccessDenied · CloudFront URL → 200 · SQLi/XSS query → 403 · burst of 300 requests → 403s.
**Cost:** WAF $5/month per web ACL + $1 per rule (prorated hourly) + $0.60 per million requests. Destroy after Week 3 demo
if budget is tight.
