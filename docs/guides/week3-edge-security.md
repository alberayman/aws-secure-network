# Week 3: Edge security, WAF, DDoS and content delivery (step by step)

**Goal:** a static site served by CloudFront from a **private** S3 bucket, protected by an AWS WAF web ACL (managed rules, rate limit, geo block) and Shield Standard. Attacks are logged and raise an alarm. Route 53 gives the app a name and a health check.
**Gate to pass:** the direct S3 URL is denied, the CloudFront URL works, SQL injection and XSS requests get **HTTP 403**, and the alarm email arrives.

**Region rule:** CloudFront is global, but a **WAF web ACL for CloudFront, its log group and its alarm must be in us-east-1 (N. Virginia)**. Switch the console region before you open WAF or CloudWatch for those.

| Task | Member | Terraform files | Switch |
|---|---|---|---|
| 3.1 Route 53, health check, edge diagram | 1 | `envs/dev/dns.tf` | `enable_edge` |
| 3.2 Site content, cache tests | 2 | `envs/dev/site_content.tf` | `enable_edge` |
| 3.3 Global Accelerator vs CloudFront, Firewall Manager | 3 | none (design docs) | - |
| 3.4 S3 + CloudFront + WAF + DDoS plan | 4 | `modules/edge/*` | `enable_edge` |
| 3.5 WAF logs, SNS, alarm, dashboard | 5 | `envs/dev/waf_monitoring.tf` | `enable_edge` |
| 3.6 CI findings, demo | 6 | `.github/workflows/ci.yml` | - |

**Order:** 3.4 builds CloudFront first (it takes 5 to 15 minutes to deploy). While it deploys, 3.1, 3.2 and 3.3 work in parallel. Then 3.5, then the attack tests.

---

## 3.1 Member 1: Route 53, health check, edge architecture

### Console steps
**A. Private hosted zone** (no domain purchase needed)
1. **Route 53** > **Hosted zones** > Create. Name `secnet.internal`, type **Private hosted zone**, region eu-west-1, VPC `secnet-vpc`.
2. **Create record**: name `app`, type **A**, **Alias** ON, *Alias to Application and Classic Load Balancer*, eu-west-1, `secnet-alb`, *Evaluate target health* ✔.
3. From the hub web server (Session Manager): `curl http://app.secnet.internal`. A private zone resolves only inside its VPC; from your laptop the name does not exist.

**B. Health check**
1. **Health checks** > Create `secnet-alb-health`: *Endpoint*, domain name = the ALB DNS name, HTTP, port 80, path `/`, interval 30 s, failure threshold 3.
2. After 1 to 2 minutes it shows **Healthy**. Failure test: **EC2** > Target groups > `secnet-tg` > deregister the web instance, wait 2 to 3 minutes for **Unhealthy**, then register it again.

**C. Failover design** (document it, building is optional because it needs a public domain): a **primary** record pointing to the ALB with the health check attached, and a **secondary** record pointing to CloudFront for a maintenance page. Route 53 answers with the secondary only while the primary is unhealthy. Write `docs/week3/route53-design.md` with a diagram and a table (record, type, routing policy, health check, TTL).

**D. Edge architecture diagram** `docs/architecture/week3-edge.png`: User → Route 53 → CloudFront (WAF + Shield Standard) → S3 via OAC, with the optional ALB origin for `/app/*`.

### Terraform (`envs/dev/dns.tf`)
`aws_route53_zone.private` (with a `vpc {}` block, which makes it private), `aws_route53_record.app` (alias to `module.compute.alb_dns_name` / `alb_zone_id`), and `aws_route53_health_check.alb`. Each has `count = var.enable_edge ? 1 : 0`.

### Check it worked
Screenshots: `curl app.secnet.internal` working inside the VPC, the health check Healthy, then Unhealthy, then Healthy again, and the diagram.

---

## 3.2 Member 2: origin content and cache tests

### Console steps
1. When 3.4's bucket exists: **S3** > `secnet-site-…` > **Upload** this `index.html`:
```html
<!doctype html><html><head><title>secnet</title></head><body><h1>secnet static site</h1><p>Served by CloudFront from a private S3 bucket.</p></body></html>
```
2. Cache test from your laptop (use your CloudFront domain):
```bash
CF=https://dxxxxxxxxxxxx.cloudfront.net
curl -sI $CF/index.html | grep -iE "^HTTP|x-cache|^age"     # 1st: Miss from cloudfront
curl -sI $CF/index.html | grep -iE "^HTTP|x-cache|^age"     # 2nd: Hit from cloudfront + age
for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" $CF/index.html; done
```
3. After changing the file, run **CloudFront** > distribution > **Invalidations** > Create `/index.html`. Explain in the doc why caching makes this step necessary.
4. Write `docs/week3/cache-test.md` with the commands, the Miss/Hit proof and the timing table.

### Terraform (`envs/dev/site_content.tf`)
`aws_s3_object.index` uploads the page to `module.edge[0].site_bucket_name` with `content_type = "text/html"`. Without the content type, browsers download the file instead of showing it.

---

## 3.3 Member 3: Global Accelerator vs CloudFront, Firewall Manager

### Console steps
1. Write `docs/week3/ga-vs-cloudfront.md` in your own words:

| Question | CloudFront | Global Accelerator |
|---|---|---|
| What it does | caches content at edge locations | carries traffic over the AWS backbone to your endpoint |
| Layer | HTTP/HTTPS (7) | TCP/UDP (4) |
| Caching | yes | no |
| Static IPs | no | 2 anycast IPs |
| Best for | websites, downloads, cacheable APIs | games, VoIP, non-HTTP, fast multi-region failover |
| Pricing idea | per request + data out | hourly fee + data transfer premium |
| Our choice | ✅ static site | not needed |

2. Optional lab, delete it the same day. **Global Accelerator** > Create: Standard, listener TCP 80, endpoint group eu-west-1, endpoint `secnet-alb`. When it shows **Deployed**, run `curl http://<static-ip>`, take a screenshot, then **disable and delete** it (≈$0.025/h + data).
3. **Firewall Manager** (document only, one page): it centrally applies WAF, Shield Advanced, security group and Network Firewall policies across all accounts in an AWS Organization. It needs Organizations, a delegated admin account and AWS Config. Explain why it does not apply to our single account.

### Terraform
None. Global Accelerator's API lives in us-west-2 and is not worth a provider alias for a one-day demo.

---

## 3.4 Member 4: S3 + CloudFront + WAF + DDoS plan

### Console steps
**A. Private bucket**
1. **S3** > Create `secnet-site-<ACCOUNT_ID>`: Block all public access ON, Versioning ON, SSE-S3. Do **not** enable *Static website hosting* (that needs a public bucket).

**B. CloudFront with Origin Access Control (OAC)**
1. **CloudFront** > Create distribution. Origin domain: pick the bucket entry ending `.s3.eu-west-1.amazonaws.com`.
2. **Origin access**: *Origin access control settings (recommended)* > Create new OAC (sign requests: always).
3. Viewer protocol policy **Redirect HTTP to HTTPS**. Cache policy **CachingOptimized**. Response headers policy **SecurityHeadersPolicy**. Price class **North America and Europe**.
4. Web Application Firewall: **Do not enable security protections** (you build your own web ACL in C). Default root object `index.html`. Create.
5. A banner offers **Copy policy**. Copy it, then go to **S3** > bucket > **Permissions** > **Bucket policy** > Edit > paste > Save. It lets only this distribution read (`AWS:SourceArn` condition).
6. When the status is **Deployed**: `https://<id>.cloudfront.net/index.html` works, and `https://secnet-site-….s3.eu-west-1.amazonaws.com/index.html` returns **AccessDenied**.

**C. WAF web ACL** (switch the region to **us-east-1**)
1. **WAF & Shield** > **Web ACLs** > Create: name `secnet-cf-acl`, resource type **Amazon CloudFront distributions**, add your distribution.
2. **Add managed rule groups** > AWS managed rule groups. Enable *Core rule set*, *Known bad inputs*, *SQL database* and *Amazon IP reputation list*.
3. **Add my own rules** > *Rate-based rule* `rate-limit`: 100 requests, 5-minute window, aggregate by source IP, action **Block**.
4. **Add my own rules** > *Rule builder* `geo-block`: *Originates from a country in* North Korea (KP), action **Block**.
5. Default action **Allow**. Priority order: managed rules, then rate, then geo. CloudWatch metrics ON for each rule. Create.

**D. Attack tests** (only against **your own** distribution)
```bash
curl -G -s -o /dev/null -w "%{http_code}\n" "$CF/index.html" --data-urlencode "id=1' OR '1'='1"          # SQLi → 403
curl -G -s -o /dev/null -w "%{http_code}\n" "$CF/index.html" --data-urlencode "q=<script>alert(1)</script>"   # XSS → 403
for i in $(seq 1 300); do curl -s -o /dev/null -w "%{http_code}\n" "$CF/index.html"; done | sort | uniq -c       # rate limit → some 403 (may take 1 to 2 min)
```
**WAF** > web ACL > **Sampled requests** shows which rule blocked each request. Geo test: temporarily add your own country, load the page (403), then remove it.

**E. Shield + DDoS mitigation plan** (`docs/week3/ddos-plan.md`, document only)
- **Shield Standard**: automatic and free on CloudFront and Route 53 (layer 3/4).
- **Shield Advanced**: about $3,000/month with a 1-year commitment. It adds the Shield Response Team, cost protection and attack reports. We document it but do not buy it.
- Plan sections:
  - assets to protect;
  - layers (CloudFront absorbs floods, WAF rate rules, origin reachable only through CloudFront in production, auto scaling);
  - detection (3.5 alarm);
  - response steps (lower the rate limit, add IP-set or geo blocks, contact AWS Support);
  - a post-incident review checklist.

**Delete before Terraform**:
1. Disassociate and delete the web ACL.
2. **Disable** the distribution, wait until it is disabled, then delete it.
3. Empty and delete the bucket.

### Terraform (`terraform/modules/edge/`)
| Block | Note |
|---|---|
| `versions.tf` `configuration_aliases = [aws.us_east_1]` | the module needs two providers. `envs/dev/main.tf` passes `aws` and `aws.us_east_1` |
| `aws_s3_bucket.site` + public access block + SSE + versioning | step A |
| `aws_cloudfront_origin_access_control.site` | step B2 |
| `aws_wafv2_web_acl.site` (`provider = aws.us_east_1`, `scope = "CLOUDFRONT"`) | step C. A `dynamic "rule"` loops over the 4 managed groups, then the rate and geo rules |
| `aws_cloudfront_distribution.site` | step B3. `web_acl_id` is the web ACL **ARN** (WAFv2). The cache policy and security headers policy IDs are the AWS-managed ones |
| `aws_s3_bucket_policy.site` | step B5, the same `AWS:SourceArn` condition |

Apply:
```bash
# terraform.tfvars: enable_edge = true
terraform init            # the first time a module with a new provider alias appears
terraform plan -out w3.tfplan && terraform apply w3.tfplan     # CloudFront takes 5 to 15 minutes
terraform output cloudfront_url
```
To geo-test through code, set `waf_blocked_countries = ["KP", "PT"]` (your country), apply, test, and set it back.

### Check it worked
Screenshots:
- Block Public Access ON, and the direct S3 URL denied
- CloudFront URL 200
- SQLi and XSS 403
- the rate-limit counts
- WAF sampled requests naming the rule

---

## 3.5 Member 5: WAF logs, alarm, dashboard (region us-east-1)

### Console steps
1. **CloudWatch** > **Log groups** > Create `aws-waf-logs-secnet` (the prefix `aws-waf-logs-` is mandatory), retention 14 days.
2. **WAF** > `secnet-cf-acl` > **Logging and metrics** > Enable. Destination: that log group.
3. **SNS** > Topics > Create *Standard* `secnet-alerts` > **Create subscription**: Email, your address, then **confirm the email**.
4. **CloudWatch** > **Alarms** > Create > Select metric > **WAFV2** > *Rule, WebACL*: `secnet-cf-acl`, Rule `ALL`, metric **BlockedRequests**. Sum, 5 minutes, **> 5**, action: notify `secnet-alerts`, name `secnet-waf-blocked`.
5. **Dashboards** > Create `secnet-waf`. Add a line widget with AllowedRequests and BlockedRequests, and a Logs table widget on the log group:
```
fields @timestamp, action, terminatingRuleId, httpRequest.clientIp, httpRequest.uri
| filter action = "BLOCK" | sort @timestamp desc | limit 20
```
6. Re-run the attack tests in 3.4 D. Within about 5 to 10 minutes the alarm goes **In alarm** and you receive the email.

### Terraform (`envs/dev/waf_monitoring.tf`)
- `aws_cloudwatch_log_group.waf` + `aws_cloudwatch_log_resource_policy.waf` (lets the log delivery service write) + `aws_wafv2_web_acl_logging_configuration.this`.
- `aws_sns_topic.alerts` + `aws_sns_topic_subscription.email` (uses `alert_email`, so **click the confirm link** or no alert arrives).
- `aws_cloudwatch_metric_alarm.waf_blocked` with dimensions `WebACL` + `Rule = ALL`. CloudFront-scope metrics have no `Region` dimension. If the alarm stays *Insufficient data*, compare its dimensions with what **CloudWatch** > **Metrics** > **WAFV2** shows and adjust.
- Build the dashboard in the console, then (optional) **Actions** > **View/edit source** to paste its JSON into an `aws_cloudwatch_dashboard` resource.

### Check it worked
Log lines for the blocked requests, the alarm **In alarm** after the test, the email received, a dashboard screenshot.

---

## 3.6 Member 6: CI findings, docs, demo

1. Review the edge pull request:
   - the bucket is not public;
   - OAC is used;
   - the WAF scope is `CLOUDFRONT` in us-east-1;
   - no hard-coded account ID or email.
2. Checkov (CI job `security-scan`) will flag things such as missing S3 access logging, CloudFront without a custom TLS certificate, or RDS without Multi-AZ. For **each** finding, either fix it or justify it with an inline comment such as `#checkov:skip=CKV_AWS_18:lab bucket, access logs not required`. Record your decisions in `docs/week3/ci-findings.md`. Once the list is clean, set `soft_fail: false` in `ci.yml`.
3. Thursday's demo (15 minutes):
   - the site
   - an attack returning 403
   - the alarm email
   - the green CI run
4. `docs/week3/README.md` links all five deliverables: CloudFront + S3 lab, WAF rule set, DDoS mitigation plan, edge architecture, Route 53/health check design.

### Cost
The WAF costs $5/month per web ACL + $1 per rule per month (prorated hourly) + $0.60 per million requests. If the budget is tight, set `enable_edge = false` after the demo and back to `true` for the final presentation.
