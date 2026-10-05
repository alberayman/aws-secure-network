# Week 1: VPC core architecture

Guide: [`docs/guides/`](../guides/) · Evidence: [`docs/evidence/week1/`](../evidence/week1/)

## Deliverables

| Deliverable | Member(s) | Status | Link |
|---|---|---|---|
| VPC design | 1 Taghride | Console lab 1.1 done by Alber (2026-10-05); Terraform pending | [resource map](../evidence/week1/w1-1.1-console-resource-map.png) |
| Subnet / CIDR plan | 1 Taghride | Not started | |
| EC2 / ALB / RDS deployment | 2 Ahlam | Not started | |
| SG / NACL rules matrix | 4 Asmaa | Private NACL + default SG done in console lab 1.1 by Alber; full matrix pending | [NACL rules](../evidence/week1/w1-1.1-nacl-rules-Inbound.png) |
| Architecture diagram | 1 Taghride | Not started | |
| Connectivity test results | 2 Ahlam | Not started | |
| Bastion vs SSM comparison (extra, answers "bastion/SSM access") | 4 Asmaa, 2 Ahlam | Not started | |

## What we built

### Task 1.1 – Hub VPC (console lab, 2026-10-05, done by Alber as `secnet-lab`)

Built by hand with **VPC and more** to learn each setting; it is deleted before the Terraform version is applied (console and Terraform must not both own a resource).

- VPC `secnet-vpc` (`vpc-0cbf713505aadf521`), 10.0.0.0/16, eu-west-1, DNS hostnames + resolution on.
- Subnets: public1 10.0.1.0/24 (eu-west-1a), public2 10.0.2.0/24 (eu-west-1b), private1 10.0.11.0/24 (eu-west-1a), private2 10.0.12.0/24 (eu-west-1b).
- Internet gateway `igw-08a04c9ed87eaeac8`; one zonal NAT gateway `nat-08f6caabde94baf4b` in public1 (single NAT = cheaper, but one AZ is a single point of failure for private egress).
- Route tables: `secnet-rtb-public` (0.0.0.0/0 → IGW), `secnet-rtb-private1/2` (0.0.0.0/0 → NAT). The console makes one private table per AZ; our Terraform uses one shared private table.
- Default security group `sg-0e4b7f6e71f4aef4c` emptied (no inbound, no outbound) – CIS / Security Hub EC2.2.
- Private NACL `secnet-private-nacl` (`acl-054a448ae2cfc214f`) associated with both private subnets:
  - Inbound: 100 all from 10.0.0.0/16 · 110 TCP 1024-65535 from 0.0.0.0/0 · 120 UDP 1024-65535 from 0.0.0.0/0 · * deny.
  - Outbound: 100 all to 0.0.0.0/0 · * deny.
  - Rules 110/120 exist because NACLs are stateless: return traffic for connections the private hosts open through the NAT arrives on ephemeral ports.

## Tests (command · expected · actual)

| # | Command | Expected | Actual | Screenshot |
|---|---|---|---|---|
| 1.1-a | Console: VPC `secnet-vpc` > Resource map | 4 subnets in 2 AZs, IGW, 1 NAT, public + private route tables | 4 subnets (1a/1b), `secnet-igw`, `secnet-nat-public1-eu-west-1a`, 4 route tables (incl. unused main) | [resource map](../evidence/week1/w1-1.1-console-resource-map.png) |
| 1.1-b | Console: Subnets > public2 > Route table | 10.0.0.0/16 → local, 0.0.0.0/0 → IGW | `secnet-rtb-public`: local + 0.0.0.0/0 → `igw-08a04c9ed87eaeac8` | [rt-public](../evidence/week1/w1-1.1-rt-public.png) |
| 1.1-c | Console: Subnets > private2 > Route table | 10.0.0.0/16 → local, 0.0.0.0/0 → NAT, no IGW route | `secnet-rtb-private2-eu-west-1b`: local + 0.0.0.0/0 → `nat-08f6caabde94baf4b` | [rt-private](../evidence/week1/w1-1.1-rt-private.png) |
| 1.1-d | Console: Security groups > `sg-0e4b7f6e71f4aef4c` > Inbound / Outbound | No rules on either tab | "No security group rules found" on both; default VPC's SG untouched | [inbound](../evidence/week1/w1-1.1-default-sg-empty-Inbound.png) · [outbound](../evidence/week1/w1-1.1-default-sg-empty-Outbound.png) |
| 1.1-e | Console: Network ACLs > `secnet-private-nacl` > Inbound / Outbound | In: 100, 110, 120, * deny. Out: 100, * deny | Matches exactly (4 inbound, 2 outbound) | [inbound](../evidence/week1/w1-1.1-nacl-rules-Inbound.png) · [outbound](../evidence/week1/w1-1.1-nacl-rules-Outbound.png) |
| 1.1-f | Console: Network ACLs > `secnet-private-nacl` > Subnet associations | private1 + private2 on the custom NACL; public subnets stay on the main NACL | private1 (10.0.11.0/24) + private2 (10.0.12.0/24) associated; main NACL now 2 subnets | [associations](../evidence/week1/w1-1.1-nacl-associations.png) |
| 1.1-g | Terraform: `terraform apply tf.plan` then `terraform plan` (drift check) | 68/68 resources; second plan reports no differences | Apply complete after one fix-up (see Problems); `No changes. Your infrastructure matches the configuration.` | [outputs](../evidence/week1/w1-1.1-tf-outputs.png) · [no-changes](../evidence/week1/w1-1.1-tf-plan-no-changes.png) |
| 1.4-a | Mac: `curl -s -o /dev/null -w "%{http_code}" http://<alb_url>` | 200 – internet reaches the web server only through the ALB | `200`; browser shows "secnet web server" from ip-10-0-11-110 (HTTP, "Not Secure" until Week 3 HTTPS) | [alb-curl-200](../evidence/week1/w1-1.4-alb-curl-200.png) · [browser](../evidence/week1/w1-1.4-alb-browser.png) |
| 1.4-b | Mac: `nc -zv -G 5 <db_endpoint> 3306` | Fails – RDS has no public IP (`publicly_accessible = false`), endpoint resolves to a private 10.0.x address | `connectx … port 3306 (tcp) failed: Network is unreachable`; `dig +short <db_endpoint>` = `10.0.11.187` (private, private1 subnet). Note: proves no public path; SG rule itself to be tested in Week 2 from a non-web host | [db-blocked](../evidence/week1/w1-1.4-db-from-internet-blocked.png) · [dns](../evidence/week1/w1-1.4-db-dns-private.png) |
| 1.4-c | SSM: `aws ssm start-session --target i-0a58dd6834802446f`, then `curl -s localhost` and `bash -c '</dev/tcp/<db_endpoint>/3306'` | Shell without SSH key or open port 22; web page served; RDS port 3306 reachable from EC2 | Session `secnet-lab-…` opened; `<h1>secnet web server</h1>` from ip-10-0-11-110; `3306 OPEN` | [ssm-db-open](../evidence/week1/w1-1.4-ssm-db-open.png) |
| 1.5-a | GitHub Actions: `terraform-ci` on `main` | fmt, validate, TFLint pass; Checkov soft-fail | Run #5 (commit 403c1be) green | [ci-green](../evidence/week1/w1-1.5-ci-green.png) |

## Problems and how we fixed them

| Date | Problem | Cause | Fix |
|---|---|---|---|
| 2026-10-04 | `terraform-ci` failed (exit 2) on runs #1–#4 | TFLint `terraform_required_version` / `terraform_required_providers` warnings: modules had no `versions.tf` | Added `versions.tf` to all 5 modules (Terraform ≥ 1.10, AWS ≥ 5.80 < 6.0); run #5 green |
| 2026-10-05 | VPC wizard defaults did not match the CIDR plan | Wizard proposes its own subnet CIDRs, NAT = None, S3 gateway endpoint on | Customised CIDRs (and fixed a typo `10.0.120/24` → `10.0.12.0/24`), NAT = Zonal in 1 AZ, endpoints = None |
| 2026-10-05 | First Terraform apply: 2 of 68 failed (CloudWatch metric filters), then retry failed again | (1) `default_value` + `dimensions` not allowed together; (2) metric-filter dimensions must be log fields, not fixed text – not catchable by offline validate/mocks | One namespace per VPC (`secnet/Network/<vpc>`), no dimensions, default 0; alarms + dashboard updated; apply 2 added / 3 changed |
| 2026-10-05 | Private NACL created but protected nothing | Creating a NACL does not attach it; the private subnets stayed on the allow-all main NACL | Edited subnet associations to private1 + private2, re-verified (test 1.1-f) |

## Cost and cleanup

Hours with each switch on, Cost Explorer screenshot, `make sleep` runs.
