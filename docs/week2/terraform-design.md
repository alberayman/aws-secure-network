# Week 2 Terraform design review (step 8)

Date: 2026-11-17 · Reviewed by: Alber · Input: the console lab of 2026-10-18 ([README](README.md))

The console lab built every Week 2 piece by hand, tested it and deleted it. Before switching
`enable_hybrid = true`, the existing Terraform was reviewed against what the lab taught us.

## What the code already had

| Piece | Where | Status |
|---|---|---|
| Spoke VPCs A/B, one subnet each, no IGW/NAT, explicit route-table association | `modules/connectivity/spokes.tf` | kept |
| Peering hub ↔ A + routes; TGW, hub/B attachments, routes | `modules/connectivity/peering.tf`, `tgw.tf` | kept, hub attachment moved (D1) |
| Private NACL opens to spokes and on-prem when hybrid is on | `modules/vpc` (`extra_allowed_cidrs`) | kept |
| SSM interface endpoints (`ssm`, `ssmmessages`, `ec2messages`) in **both** spokes; S3 gateway endpoint on the hub private route table | `envs/dev/endpoints.tf` | kept |
| Test instance per spoke (AL2023, IMDSv2, encrypted, SSM profile, python web server :80) | `envs/dev/spoke_tests.tf` | kept |
| PrivateLink: NLB in Spoke B, endpoint service, hub interface endpoint | `envs/dev/privatelink.tf` | fixed (D4) |

## Decisions

**D1 – Dedicated TGW attachment subnets (new).** The console lab showed that AWS does not
evaluate NACL rules for traffic from a TGW to instances in the same subnet as the attachment
([AWS docs](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-nacls.html)). The hub attachment now
uses two /28 subnets (`10.0.254.0/28` AZ a, `10.0.254.16/28` AZ b) with their own route table
(local only) and an open NACL, as AWS recommends. TGW traffic now crosses into the private
subnets, so the private NACL filters it. Created only when `enable_hybrid = true`.
Alternatives rejected: keep the attachment in the workload subnets (finding stays open);
restrictive NACL on the /28s (double filtering, no gain).

**D2 – SSM endpoints in both spokes (kept).** The console lab used Spoke A only to save cost.
Terraform keeps both (about +$0.033/h) so Spoke B → hub can be tested from inside Spoke B,
which closes the test gap from the console lab. S3 gateway endpoint: full-access policy in the
lab. Restricting it to our own account (`aws:ResourceAccount`) is a production hardening step;
it would also block AWS-owned buckets the SSM agent uses unless they are listed.

**D3 – Spoke test instances (kept).** Both get the SSM profile because both spokes now have
endpoints. SGs allow ICMP + HTTP from `10.0.0.0/8` and on-prem, so a failed spoke-to-spoke
test is caused by routing, not by a security group.

**D4 – PrivateLink fixes.**
1. The NLB is created **with a security group** (TCP 80 from `10.0.0.0/8`, egress TCP 80 to Spoke B).
   An NLB cannot get security groups after creation.
2. `acceptance_required = true`, and the provider accepts the hub endpoint in code
   (`aws_vpc_endpoint_connection_accepter`), so the approval is reviewed and logged.
3. The hub endpoint is placed **only in hub private subnet 1**. The NLB is in one AZ, so the
   service exists only there; the old code asked for both subnets and would have failed on apply.

## Expected test changes after the build

| Test | Console lab (18 Oct) | Expected with Terraform |
|---|---|---|
| Hub → Spoke A ping | FAIL (NACL had no spoke rule) | **OK** (rule for 10.1.0.0/16) |
| Hub → Spoke B ping | OK (NACL bypassed) | OK, now **because of** the NACL rule |
| NACL drill: deny ICMP from 10.2.0.0/16 | not possible (bypassed) | **FAIL** while the deny is in place |
| Spoke A → hub :80 | FAIL | FAIL (web SG: ALB only) |
| Spoke A → Spoke B | FAIL | FAIL (peering not transitive) |
| Spoke B → hub ping (from Spoke B) | not testable | **OK** |
| PrivateLink curl / port 22 | OK / closed | OK / closed |

## Cost with hybrid on (eu-west-1, approx.)

TGW attachments 2 × $0.05 · interface endpoints 7 × $0.011 · NLB ≈ $0.025 · 2 × t3.micro ≈ $0.023
→ **≈ $0.23/h** on top of the hub tier. Session use only, then targeted destroy.
