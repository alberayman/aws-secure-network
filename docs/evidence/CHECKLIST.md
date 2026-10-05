# Evidence checklist – Project 2 (complete set, could be submitted alone)

Tick each box when the evidence file exists **and** the result is written in the week README.
File names: `w<week>-<task>-<what>.png` in `docs/evidence/week<N>/`. Blur access key IDs (even partial), secret keys, VPN PSKs, public IPs and Client VPN configs; the account ID may stay visible (decision 2026-10-05, see change log).
For every task keep **one console screenshot + one Terraform proof** (plan summary, apply complete, `terraform output`).

## Guide 0 – Foundations (day 1)
- [ ] `w0-0.1-root-mfa.png` – root MFA assigned
- [ ] `w0-0.1-iam-users-mfa.png` – team users in `project-team`, MFA on
- [ ] `w0-0.2-budget.png` – `secnet-monthly` with 4 alerts
- [ ] `w0-0.3-sts-identity.txt` – `aws sts get-caller-identity` (blur the access key ID if it shows)
- [ ] `w0-0.4-state-bucket.png` – versioning + Block Public Access ON
- [ ] `w0-0.7-branch-protection.png` – `main` protected, secret scanning ON

## Week 1 – VPC core architecture
| # | Booklet deliverable | Evidence files | Where it is written up | Done |
|---|---|---|---|---|
| 1 | VPC design | `w1-1.1-resource-map.png`, `w1-1.1-tf-apply.png` | `docs/week1/README.md` | [ ] |
| 2 | Subnet / CIDR plan | – | `docs/architecture/cidr-plan.md` | [ ] |
| 3 | EC2 / ALB / RDS deployment | `w1-1.2-alb-page.png`, `w1-1.2-ssm-session.png`, `w1-1.2-mysql-prompt.png`, `w1-1.2-tf-output.txt` | `docs/week1/README.md` | [ ] |
| 4 | SG / NACL rules | `w1-1.3-sg-rules.png`, `w1-1.1-nacl-rules.png` | `docs/week1/sg-nacl-matrix.md` | [ ] |
| 5 | Architecture diagram | `docs/architecture/week1.png` (+ `.drawio`) | `docs/architecture/` | [ ] |
| 6 | Connectivity test results | `w1-1.3-curl-timeout.png`, `w1-1.3-rds-blocked.png`, `w1-1.3-reachability.png` (optional) | test table in `docs/week1/README.md` | [ ] |
| + | Bastion vs SSM (answers "bastion/SSM access") | `w1-1.6-bastion-ssh.png`, `w1-1.6-ssm-history.png` (optional lab) | `docs/week1/bastion-vs-ssm.md` | [ ] |
| + | CloudTrail + log bucket | `w1-1.4-cloudtrail-event.png`, `w1-1.4-s3-awslogs.png` | `docs/week1/README.md` | [ ] |
| + | Repo + CI | `w1-1.5-ci-green.png` | `docs/week1/README.md` | [ ] |

## Week 2 – Advanced connectivity & hybrid networking
| # | Booklet deliverable | Evidence files | Where it is written up | Done |
|---|---|---|---|---|
| 7 | Hub-and-spoke / TGW diagram | `docs/architecture/week2-hub-spoke.png` | `docs/architecture/` | [ ] |
| 8 | Peering / endpoint setup | `w2-2.2-peering-active.png`, `w2-2.2-tgw-attachments.png`, `w2-2.3-fleet-manager.png`, `w2-2.3-privatelink-curl.png` | `docs/week2/README.md` | [ ] |
| 9 | VPN configuration | `w2-2.2-tunnel-up.png`, `w2-2.2-ipsec-statusall.txt` (**no PSK**) | `docs/week2/README.md` | [ ] |
| 10 | Route table documentation | `w2-2.1-route-tables.json` | `docs/architecture/route-tables.md` | [ ] |
| 11 | Hybrid connectivity test report | `w2-2.4-ping-*.png` (7 tests) | `docs/week2/test-report.md` | [ ] |
| + | Client VPN (booklet task) | `w2-2.7-endpoint-available.png`, `w2-2.7-client-connected.png`, `w2-2.7-tests.png`, `w2-2.7-connection-log.png` | `docs/week2/client-vpn.md` | [ ] |
| + | Direct Connect (concepts) | – | `docs/week2/direct-connect.md` | [ ] |
| + | Flow Logs baseline | `w2-2.5-flowlog-active.png` | `docs/week2/flowlogs-baseline.md` | [ ] |

## Week 3 – Edge security, WAF, DDoS & content delivery
| # | Booklet deliverable | Evidence files | Where it is written up | Done |
|---|---|---|---|---|
| 12 | CloudFront + S3 lab | `w3-3.4-s3-denied.png`, `w3-3.4-cloudfront-200.png`, `w3-3.2-cache-miss-hit.txt` | `docs/week3/cache-test.md` | [ ] |
| 13 | WAF rule set | `w3-3.4-webacl-rules.png`, `w3-3.4-sqli-403.txt`, `w3-3.4-xss-403.txt`, `w3-3.4-rate-limit.txt`, `w3-3.4-sampled-requests.png` | `docs/week3/README.md` | [ ] |
| 14 | DDoS mitigation plan | – | `docs/week3/ddos-plan.md` | [ ] |
| 15 | Edge architecture | `docs/architecture/week3-edge.png` | `docs/architecture/` | [ ] |
| 16 | Route 53 / health check design | `w3-3.1-private-zone-curl.png`, `w3-3.1-health-healthy.png`, `w3-3.1-health-unhealthy.png` | `docs/week3/route53-design.md` | [ ] |
| + | Shield / Firewall Manager / Global Accelerator | `w3-3.3-ga-curl.png` (optional) | `docs/week3/ga-vs-cloudfront.md` | [ ] |
| + | WAF logging + alarm | `w3-3.5-waf-logs.png`, `w3-3.5-alarm-email.png`, `w3-3.5-dashboard.png` | `docs/week3/README.md` | [ ] |
| + | CI findings | `w3-3.6-checkov.png` | `docs/week3/ci-findings.md` | [ ] |

## Week 4 – Network monitoring, detection & IR
| # | Booklet deliverable | Evidence files | Where it is written up | Done |
|---|---|---|---|---|
| 17 | Flow log queries | `w4-4.4-athena-q10.png` … `q14.png`, `w4-4.4-logs-insights.png` | `docs/week4/README.md` | [ ] |
| 18 | Detection use cases | `w4-4.4-cw-ssh-alarm-email.png`, `w4-4.4-cw-reject-alarm.png`, `w4-4.4-network-dashboard.png` | `docs/week4/detection-use-cases.md` | [ ] |
| 19 | Compromised-instance IR runbook | – | `docs/runbooks/ir-runbook.md` | [ ] |
| 20 | Evidence collection notes | `w4-4.1-snapshot-pre.png`, `w4-4.1-snapshot-post.png`, `w4-4.2-pcap-hash.txt`, `w4-4.4-cloudtrail-export.csv` + hash, `w4-4.4-validate-logs.txt` | chain-of-custody table in the runbook | [ ] |
| 21 | Final secure network report | – | `docs/final-report.md` | [ ] |
| + | Traffic Mirroring | `w4-4.2-tcpdump.png`, small sample `.pcap` | `docs/week4/traffic-mirroring.md` | [ ] |
| + | Containment | `w4-4.3-sg-swapped.png`, `w4-4.3-ping-fails.png`, `w4-4.3-revoke-sessions.png` | `docs/week4/containment-checklist.md` | [ ] |
| + | Incident timeline (UTC) | – | timeline in the runbook | [ ] |

## Final checks
- [ ] Every booklet line above has a ticked row (21/21)
- [ ] `docs/change-log.md` has an entry for every apply/destroy
- [ ] Cost Explorer screenshot for the whole month: `w4-4.5-cost-explorer.png`
- [ ] Clean-up proof: `w4-4.5-tag-editor-empty.png`
- [ ] Git history shows commits across all four weeks
