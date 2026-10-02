# Team and task split – Group ONL5_ISS11_G1

We are six DEPI students working as equals (no job titles). DEPI asks every group to split the work and
show each member's part at the final presentation, so each member **leads one workstream** and **backs up** another.
Send this table to the instructor before the task-split deadline.

| # | Name | GitHub | Leads workstream | Owns (files) | Booklet deliverables led | Backs up |
|---|---|---|---|---|---|---|
| 1 | | | Networking | `modules/vpc`, `envs/dev/dns.tf` | VPC design, CIDR plan, NACL rules, diagrams, route tables, Route 53 design | 2 |
| 2 | | | Servers and database | `modules/compute` (EC2/ALB/RDS), `spoke_tests.tf`, `site_content.tf`, `victim.tf` | EC2/ALB/RDS, connectivity + hybrid test reports, cache tests, incident simulation | 1 |
| 3 | | | Hybrid connectivity | `modules/connectivity`, `client_vpn.tf`, `mirroring.tf` | peering, TGW, Site-to-Site VPN, Client VPN lab, Direct Connect design, GA comparison, Firewall Manager notes, Traffic Mirroring | 4 |
| 4 | | | Edge and access security | `modules/compute/security_groups.tf` + `iam.tf`, `endpoints.tf`, `privatelink.tf`, `modules/edge`, `isolation.tf` | SG matrix, bastion vs SSM, endpoints/PrivateLink, CloudFront + S3, WAF rules, DDoS plan, containment | 3 |
| 5 | | | Logging and incident response | `modules/monitoring`, `waf_monitoring.tf` | CloudTrail, Flow Logs, CloudWatch network alarms, WAF logs/alarm, Athena queries, detection use cases, IR runbook | 6 |
| 6 | | | Repo, CI and reporting | repo, `.github/`, `versions.tf`, `budget.tf`, `Makefile` | repo + CI, state, cost guardrails, weekly notes, final report, slides | 5 |

Decisions are made together at the daily 15-minute stand-up. Anyone can review any pull request.
