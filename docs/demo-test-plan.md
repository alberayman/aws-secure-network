# Demo test plan: every test that proves the project works

One numbered list for the whole project, written for the presenter. Each test says **what it proves**
in one sentence you can say out loud, the command, what you should see, and the evidence file.

- Placeholders like `<alb_url>` come from `terraform output` (IDs change after every rebuild).
- **Positive tests** prove something works. **Negative tests** (marked ❌ expected) prove something is
  blocked; in a security project the negative tests are the stronger proof.
- Status: ✅ passed (date) · ⬜ not run yet. Detailed steps live in `docs/guides/week*.md`;
  results are also recorded in `docs/week<N>/README.md`.

---

## Week 1: the hub (secure 3-tier app + logging)

| # | What it proves (say this) | Command / action | Expected | Evidence | Status |
|---|---|---|---|---|---|
| T1 | The website is reachable from the internet **only through the load balancer** | Mac: `curl -s -o /dev/null -w "%{http_code}\n" <alb_url>`; open it in a browser | `200`, page "secnet web server" | `week1/w1-1.4-alb-curl-200.png`, `w1-1.4-alb-browser.png` | ✅ 2026-10-05 |
| T2 | The database has **no public path** | Mac: `dig +short <db_endpoint>` then `nc -zv -G 5 <db_endpoint> 3306` | private `10.0.x.x` address; connection fails ❌ | `w1-1.4-db-dns-private.png`, `w1-1.4-db-from-internet-blocked.png` | ✅ 2026-10-05 |
| T3 | The web server cannot be reached directly, only via the ALB | Mac: `curl -m 5 http://<web_private_ip>` | timeout ❌ | `w1-1.3-web-direct-blocked.png` | ⬜ |
| T4 | Admins get a shell **without SSH, keys or open ports** | `aws ssm start-session --target <web_instance_id>` | shell opens; no port 22 rule exists anywhere | `w1-1.4-ssm-db-open.png` | ✅ 2026-10-05 |
| T5 | The app tier can reach the database (allowed path) | in the SSM session: `timeout 3 bash -c '</dev/tcp/<db_endpoint>/3306' && echo OPEN` (stronger: `mysql -h <db_endpoint> -u admin -p` with the password from Secrets Manager) | `OPEN` / `mysql>` prompt | `w1-1.4-ssm-db-open.png` | ✅ 2026-10-05 (port test) |
| T6 | The database rule is **least privilege**: remove it and EC2 loses access | console: delete SG rule `rds_from_ec2`, repeat T5, then `terraform apply` to restore it | timeout ❌, then OPEN again after apply (plan shows the drift) | `w1-1.3-rds-rule-removed.png` | ⬜ |
| T7 | Nothing on the internet can reach port 22 | VPC > Reachability Analyzer: IGW → web instance, port 22 (≈ $0.10) | *Not reachable*, names the blocking SG ❌ | `w1-1.3-reachability-22.png` | ⬜ optional |
| T8 | Anything launched without a security group gets **no** network access | VPC > Security groups > `default` of `secnet-vpc` | 0 inbound, 0 outbound rules | `w1-1.1-default-sg-empty-*.png` | ✅ 2026-10-05 (console lab) |
| T9 | Private subnets have a second, subnet-level filter (stateless NACL) | VPC > Network ACLs > `secnet-private-nacl` | rules 100/110/120 + deny; associated with both private subnets | `w1-1.1-nacl-*.png` | ✅ 2026-10-05 (console lab) |
| T10 | Every API call is recorded with **who** did it | create any SG in the console, wait 5–15 min: CloudTrail > Event history | `CreateSecurityGroup` with user `secnet-lab`; S3 has `AWSLogs/.../CloudTrail/` | `w1-1.4-cloudtrail-event.png` | ⬜ |
| T11 | The live environment matches the code exactly (no hidden manual changes) | `terraform plan` | `No changes.` | `w1-1.1-tf-plan-no-changes.png` | ✅ 2026-10-05 |
| T12 | Code is checked automatically before it reaches `main` | push / open a PR; GitHub Actions `terraform-ci` | fmt, validate, TFLint pass; (direct push to `main` refused once branch protection is on) | `w1-1.5-ci-green.png` | ✅ CI · ⬜ branch protection |
| T13 | Spending is guarded | Billing > Budgets `secnet-monthly`; SNS alert topic confirmed | budget $50 with 3 alerts + forecast; subscription confirmed | `w1-1.5-budget.png` | ⬜ screenshot |

## Week 2: hybrid connectivity and segmentation

| # | What it proves | Command / action | Expected | Evidence | Status |
|---|---|---|---|---|---|
| T14 | Hub ↔ Spoke A connected by **VPC peering** | hub web (SSM): `ping -c 3 <spoke_a_ip>` | replies | `w2-2.4-hub-to-spoke-a.png` | ⬜ |
| T15 | Hub ↔ Spoke B connected by **Transit Gateway** | hub web: `ping -c 3 <spoke_b_ip>`; `curl http://<spoke_b_ip>` | replies; "Spoke B service" | `w2-2.4-hub-to-spoke-b.png` | ⬜ |
| T16 | Peering is **not transitive**: Spoke A cannot use the hub to reach Spoke B | Spoke A (SSM): `ping -c 3 <spoke_b_ip>` | fails ❌ | `w2-2.4-spoke-a-to-b-blocked.png` | ⬜ |
| T17 | The office reaches the hub over an **encrypted Site-to-Site VPN** | VPN > Tunnel details; office router: `sudo ipsec statusall`, `ping -c 3 <web_private_ip>` | tunnel UP, `ESTABLISHED`, replies | `w2-2.2-vpn-up.png`, `w2-2.2-office-to-hub.png` | ⬜ |
| T18 | **Segmentation**: the office can reach the hub but not Spoke B | office router: `ping -c 3 <spoke_b_ip>` | fails ❌ (design decision, documented) | `w2-2.4-office-to-spoke-b-blocked.png` | ⬜ |
| T19 | Spokes are isolated from the internet | Spoke A: `curl -m 5 https://example.com` | fails ❌ (no IGW, no NAT) | `w2-2.4-spoke-no-internet.png` | ⬜ |
| T20 | Private hosts are managed **without internet**, through VPC endpoints | Systems Manager > Fleet Manager; SSM session on a spoke instance | both spoke instances online; session opens | `w2-2.3-fleet-manager.png` | ⬜ |
| T21 | **PrivateLink** shares one service with no routing between the VPCs | hub web: `curl http://<privatelink_dns>` | "Spoke B service" | `w2-2.3-privatelink.png` | ⬜ |
| T22 | A remote user connects with **Client VPN** (mutual TLS certificates) | connect the VPN client; `ping <web_private_ip>` | connected; replies | `w2-2.7-client-vpn-ping.png` | ⬜ |
| T23 | Even on the VPN, security groups still apply | `curl -m 5 http://<web_private_ip>` | fails ❌ (web only accepts HTTP from the ALB) | `w2-2.7-client-vpn-http-blocked.png` | ⬜ |
| T24 | VPN users only reach what they are authorized for | `ping <spoke_b_ip>` | fails ❌ (no authorization rule for 10.2.0.0/16) | `w2-2.7-client-vpn-spoke-b-blocked.png` | ⬜ |
| T25 | Remote access is audited | CloudWatch log group `/secnet/client-vpn` | certificate common name, connect time, bytes | `w2-2.7-client-vpn-log.png` | ⬜ |
| T26 | All traffic is recorded (Flow Logs) | VPC > each VPC > Flow logs; S3 `.log.gz` files | status Active on every VPC; can name top 3 talkers | `w2-2.5-flow-logs-active.png` | ⬜ |

## Week 3: edge security (CloudFront, WAF, Route 53)

| # | What it proves | Command / action | Expected | Evidence | Status |
|---|---|---|---|---|---|
| T27 | The S3 bucket behind the site is **private** | open the direct S3 object URL | `AccessDenied` ❌ | `w3-3.4-s3-direct-denied.png` | ⬜ |
| T28 | The site is served over HTTPS through CloudFront only | `curl -s -o /dev/null -w "%{http_code}\n" $CF/index.html` | `200` | `w3-3.4-cloudfront-200.png` | ⬜ |
| T29 | WAF blocks **SQL injection** | `curl -G … "$CF/index.html" --data-urlencode "id=1' OR '1'='1"` | `403` ❌ | `w3-3.4-sqli-403.png` | ⬜ |
| T30 | WAF blocks **cross-site scripting** | `curl -G … --data-urlencode "q=<script>alert(1)</script>"` | `403` ❌ | `w3-3.4-xss-403.png` | ⬜ |
| T31 | WAF **rate limit** stops floods (basic DDoS defence) | 300 requests in a loop, `sort \| uniq -c` | mix of `200` and `403` | `w3-3.4-rate-limit.png` | ⬜ |
| T32 | WAF can **geo-block** a country | add your own country to the geo rule, reload, then remove it | `403`, then `200` | `w3-3.4-geo-block.png` | ⬜ |
| T33 | Attacks are **logged and alerted** | WAF > Sampled requests; CloudWatch alarm; email inbox | rule name per blocked request; alarm *In alarm*; email received | `w3-3.5-waf-alarm.png`, `w3-3.5-alarm-email.png` | ⬜ |
| T34 | Internal DNS name and **health check** work (failover design) | inside the VPC: `curl app.secnet.internal`; Route 53 health check | page loads; Healthy → Unhealthy → Healthy | `w3-3.1-route53.png`, `w3-3.1-health-check.png` | ⬜ |

## Week 4: detection and incident response (drill IR-001)

| # | What it proves | Command / action | Expected | Evidence | Status |
|---|---|---|---|---|---|
| T35 | Suspicious activity leaves traces | run the 4.1 simulation on `secnet-victim` (port sweep, SSH attempts, odd outbound) | flow-log `REJECT` lines from the victim's IP | `w4-4.1-reject-lines.png` | ⬜ |
| T36 | Detection is **automatic** | CloudWatch alarms `secnet-hub-rejected-flows-spike`, `secnet-hub-ssh-attempt` | *In alarm*; email received | `w4-4.4-alarms-email.png` | ⬜ |
| T37 | We can investigate: **who, what, when** | Athena saved queries 11 (port 22), 12 (port scan), 14 (host timeline) | victim IP scanning Spoke A; timeline matches T0/T1 | `w4-4.4-athena-*.png` | ⬜ |
| T38 | Evidence is **preserved before** containment | EC2 > Snapshots, tag `Case=IR-001`, `Phase=pre-containment` | snapshot `completed` before isolation time | `w4-4.1-evidence-snapshot.png` | ⬜ |
| T39 | The compromised host is **contained** while the site stays up | `isolate_victim = true` → plan → yes → apply; re-run part of the simulation; T1 again | victim traffic REJECT; website still `200` | `w4-4.3-isolated.png` | ⬜ |
| T40 | Every response action is **audited** | CloudTrail: `ModifyInstanceAttribute` / SG change | user, time, source IP of the containment | `w4-4.3-cloudtrail-containment.png` | ⬜ |
| T41 | Clean shutdown, nothing left billing | Cost Explorer next day; Resource Groups > Tag Editor `Project=secure-network` | ≈ $0; no leftover resources | `w4-4.5-cost-zero.png` | ⬜ (last day) |

---

## Live demo shortlist (about 10 minutes)

Run these live; show the screenshots for everything else. Order tells the story: front door → walls →
connections → edge → incident.

1. **T1** website via ALB → 2. **T2** database has no public path → 3. **T4 + T5** SSM shell and the allowed DB path →
4. **T16** peering not transitive → 5. **T18** office segmented from Spoke B → 6. **T21** PrivateLink →
7. **T29 / T30** SQLi and XSS get 403 → 8. **T39** contain the victim, website still up → 9. **T11** `terraform plan` = No changes.

## Before the presentation

- Rebuild the day before at the latest (CLAUDE.md freeze: no infrastructure changes in the last 24 h except re-creating the demo).
- Switches needed for the shortlist: `enable_nat`, `enable_hybrid`, `enable_vpn`, `enable_edge`, `enable_ir`. Run every shortlist test once after the rebuild and note the new IDs/URLs.
- Keep the screenshots open in a second window as the **backup** for any live test that fails (a live VPN or WAF test can be slow).
- After the presentation: `make sleep`, then the final-day destroy (Tier 3, recorded in `change-log.md`).
