# Week 3: Edge security, WAF, DDoS & content delivery

Guide: [`docs/guides/`](../guides/) · Evidence: [`docs/evidence/week3/`](../evidence/week3/)

## Deliverables

| Deliverable | Status | Link |
|---|---|---|
| CloudFront + S3 lab | Done (site + app distributions; project website live) | [`modules/edge`](../../terraform/modules/edge), [website](../../website/) |
| WAF rule set | Done (managed rules, rate limit, geo-block; drills T29–T33) | [`modules/edge/main.tf`](../../terraform/modules/edge/main.tf) |
| DDoS mitigation plan | In the final report | [final-report.md](../final-report.md) |
| Edge architecture | Done (D8: CloudFront-only ALB) | see "Design decision D8" below |
| Route 53 / health check design | Done (private zone, end-to-end health check, T34) | [`dns.tf`](../../terraform/envs/dev/dns.tf) |

## What we built

### Design decision D8: CloudFront + WAF in front of the ALB (AWS-recommended)

**Problem.** In Week 1 the ALB was open to the internet on port 80 with no WAF. Anyone could skip the edge.

**Options considered.**

| Option | How | Pros | Cons |
|---|---|---|---|
| A. Regional WAF on the ALB | WAF ACL with REGIONAL scope attached to the ALB | Simple, no traffic-flow change | Two WAF ACLs to maintain; no CDN, no edge DDoS absorption |
| **B. CloudFront in front of the ALB (chosen)** | Same CLOUDFRONT-scope WAF; ALB SG allows only the managed prefix list `com.amazonaws.global.cloudfront.origin-facing`; ALB listener returns 403 unless the secret header `X-Origin-Verify` is present | One WAF for site + app; Shield Standard at the edge; matches AWS docs "Restricting access to Application Load Balancers" | CloudFront → ALB is HTTP (no domain/ACM cert in the lab); secret header must be rotated |
| C. CloudFront VPC origins + internal ALB | ALB moves to private subnets; CloudFront reaches it through a VPC origin | No public ALB at all | Bigger change to the hub; next step for production |

**Why both controls on the ALB.** The prefix list alone would also admit *other* customers' CloudFront
distributions; the secret header proves the request came from *our* distribution.

**Trade-offs / risks (accepted for the lab).**
- Origin leg is HTTP inside AWS's network. Production: ACM certificate + `https-only` origin, or option C.
- The header value lives in Terraform state (encrypted S3 bucket) and is visible to anyone with
  `cloudfront:GetDistributionConfig`. Production: rotate it (Secrets Manager + Lambda, two values during rotation).
- The internal name `app.secnet.internal` was removed (an internal alias to a CloudFront-only ALB is refused);
  the private zone now holds `db.secnet.internal`. The Route 53 health check now tests the full path
  (CloudFront → WAF → ALB → web) over HTTPS.

**Proved by demo tests:** T1 (app 200 via CloudFront), T1b (ALB direct → 000), T29b (SQLi on the app → 403), T34.

## Tests (command · expected · actual)

Automated with `make demo ARGS="--week 3"` on 2026-11-21 16:50 UTC: **7 passed, 0 failed**
(evidence `../evidence/demo-run-2026-11-21-week3.png`, log `demo-run-20261121-1650.log`).

| # | Command | Expected | Actual | Screenshot |
|---|---|---|---|---|
| T27 | `curl https://<bucket>.s3.eu-west-1.amazonaws.com/index.html` | 403 (bucket private, OAC only) | 403 ✅ | demo-run-2026-11-21-week3.png |
| T28 | `curl <cloudfront_url>` | 200 over HTTPS | 200 ✅ | same |
| T29 | `curl -G <cloudfront_url> --data-urlencode "id=1' OR '1'='1"` | 403 (WAF SQLi) | 403 ✅ | same |
| T1b | `curl -m 6 http://<alb-dns>` | 000 (ALB accepts CloudFront only, D8) | 000 ✅ | same |
| T29b | same SQLi against `<app_url>` | 403 (WAF protects the app) | 403 ✅ | same |
| T30 | `curl -G <cloudfront_url> --data-urlencode "q=<script>…"` | 403 (WAF XSS) | 403 ✅ | same |
| T34 | web via SSM: `getent hosts db.secnet.internal`; Route 53 health check status | 10.0.x.x · checkers OK > 0 | 10.0.11.231 · 16 checkers OK ✅ | same |
| 3.6 | SNS email subscription for WAF alarms (us-east-1 `secnet-alerts`) | Subscription confirmed | confirmed ✅ | ../evidence/week3/w3-3.6-sns-subscription-confirmed.png |

| T31 | 300 × `curl <cloudfront_url>` from one IP (`make demo ARGS="--slow"`) | mix of 200 and 403 (rate rule 100 / 5 min) | 191×200 · 109×403 ✅ | ../evidence/regression-2026-11-21-full.log |
| T33 | WAF `BlockedRequests` > 5 in 5 min → CloudWatch alarm → SNS email | ALARM email | ALARM at 17:07 UTC, 83 blocked in the 17:02 period ✅ | ../evidence/week3/w3-T33-waf-alarm-email.png |

Full regression 2026-11-21 16:55 UTC (Weeks 1–3, `--slow`): **27 passed, 0 failed, 0 skipped**
(`../evidence/regression-2026-11-21-full.log`). T1 now goes through CloudFront, so Week 1 still works after D8.

| T32 | `plan -var 'waf_blocked_countries=["PT"]'` → apply → curl site + app from Lisbon; CloudWatch `BlockedRequests` Rule=geo-block; revert with a normal plan | 403 while blocked · metric > 0 · 200 after revert | 403/403 · 8 blocked by geo-block · 200/200 after revert ✅ | ../evidence/week3/w3-T32-geo-block-{403,metric,reverted-200}.png |

All Week 3 tests done (T27–T34, T1b, T29b).

## Problems and how we fixed them

- **Provider warning after D8 apply:** changing the listener default action in place from `forward` to
  `fixed-response` left the old `target_group_arn` in state ("will be an error in a future release").
  Works today. Fix: the listener is re-created clean on the next build after `make sleep`; re-check the warning then.

## Project website (site bucket)

Source: `website/` (index.html + the two diagrams), uploaded by `terraform/envs/dev/site_content.tf`
(etag = MD5, so only changed files are re-uploaded). CloudFront caches for up to a day, so after a
change invalidate the cache:

```
aws cloudfront create-invalidation --profile secnet \
  --distribution-id "$(terraform -chdir=terraform/envs/dev output -raw cloudfront_distribution_id)" --paths "/*"
```

## Cost and cleanup

Hours with each switch on, Cost Explorer screenshot, `make sleep` runs.
