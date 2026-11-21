# Week 3 (Member 2): the page CloudFront serves from the private bucket.
# The full project website (website/ at the repo root) goes live after Week 4:
# swap in website/site_content.tf.pending then.
resource "aws_s3_object" "index" {
  count        = var.enable_edge ? 1 : 0
  bucket       = module.edge[0].site_bucket_name
  key          = "index.html"
  content      = "<!doctype html><html><head><title>secnet</title></head><body><h1>secnet static site</h1><p>Served by CloudFront from a private S3 bucket.</p></body></html>"
  content_type = "text/html"
}
