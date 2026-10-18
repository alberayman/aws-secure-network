# Week 2: Advanced connectivity & hybrid networking

Guide: [`docs/guides/`](../guides/) · Evidence: [`docs/evidence/week2/`](../evidence/week2/)

## Deliverables

| Deliverable | Member(s) | Status | Link |
|---|---|---|---|
| Hub-and-spoke / TGW diagram | 1 Taghride | Not started | |
| Peering + endpoint setup | 3 Mohamed, 4 Asmaa | Not started | |
| VPN configuration (no secrets) | 3 Mohamed | Not started | |
| Route table documentation | 1 Taghride | Not started | |
| Hybrid connectivity test report | 2 Ahlam | Not started | |
| Client VPN lab + Direct Connect design (booklet task) | 3 Mohamed, 4 Asmaa | Not started | |

## What we built

### Console lab (2026-10-18, Alber) — built by hand first, deleted before the Terraform build

**Step 1: spoke VPCs.** Two spoke VPCs with one private subnet each and no IGW/NAT; each uses its VPC's main route table, which only has the `local` route.

| VPC | CIDR | Private subnet | Route table |
|---|---|---|---|
| `lab-spoke-a` (vpc-099cbb38773df319a) | 10.1.0.0/16 | `lab-spoke-a-private` 10.1.1.0/24 | `lab-spoke-a-rt` rtb-05da3a31a6664a64b (main) |
| `lab-spoke-b` (vpc-0c8f6f3b02c7d647f) | 10.2.0.0/16 | `lab-spoke-b-private` 10.2.1.0/24 | `lab-spoke-b-rt` rtb-01e1483f0d82e662e (main) |

No CIDR overlaps with the hub (10.0.0.0/16) or the office (192.168.0.0/16), so peering and the TGW can route between all of them.

Evidence: [VPCs](../evidence/week2/w2-2.2-console-spoke-vpcs.png) · [subnets](../evidence/week2/w2-2.2-console-spoke-subnets.png) · [Spoke A route table](../evidence/week2/w2-2.2-console-spoke-a-rt.png) · [route tables](../evidence/week2/w2-2.2-console-route-tables.png)

**Step 2: VPC peering hub ↔ Spoke A.** Peering `lab-pcx-hub-spoke-a` (pcx-0c8a8218991b89461) requested from `secnet-vpc` (10.0.0.0/16) and accepted by `lab-spoke-a` (10.1.0.0/16), same account and Region. Routes in both directions, so return traffic is not dropped:

| Route table | Destination | Target |
|---|---|---|
| `lab-spoke-a-rt` | 10.0.0.0/16 | pcx-0c8a8218991b89461 |
| `secnet-private-rt` (hub, Terraform-managed) | 10.1.0.0/16 | pcx-0c8a8218991b89461 |

The hub route is a manual change to a Terraform resource; it is logged in [`change-log.md`](../change-log.md) and is removed in step 7, before the Terraform build. Peering is not transitive: Spoke A will not reach Spoke B or the office through the hub.

Evidence: [peering Active](../evidence/week2/w2-2.3-console-pcx-active.png) · [Spoke A routes](../evidence/week2/w2-2.3-console-spoke-a-rt-pcx.png) · [hub private routes](../evidence/week2/w2-2.3-console-hub-private-rt-pcx.png)

**Step 3: Transit Gateway hub ↔ Spoke B.** `lab-tgw` (tgw-09f297d76edb26446, Amazon ASN 64512, DNS support and VPN ECMP on, default route table association and propagation on, auto-accept off, SG referencing off). Attachments: `lab-tgw-att-hub` (secnet-vpc, both private subnets) and `lab-tgw-att-spoke-b` (lab-spoke-b, one subnet). Both attachments are associated with the default TGW route table, which learned both VPC CIDRs by propagation.

| Route table | Destination | Target | How |
|---|---|---|---|
| TGW default RT `tgw-rtb-0f48dbdccde915a7e` | 10.0.0.0/16 | tgw-attach-0d4840dedfa42252d (hub) | Propagated |
| TGW default RT | 10.2.0.0/16 | tgw-attach-0cdfeb8c12a4827cf (Spoke B) | Propagated |
| `lab-spoke-b-rt` | 10.0.0.0/16 | tgw-09f297d76edb26446 | Static |
| `secnet-private-rt` (hub, Terraform-managed) | 10.2.0.0/16 | tgw-09f297d76edb26446 | Static, removed in step 7 |

Trade-offs (lab vs production): one TGW route table means every attachment can reach every other; production would disable default association/propagation and use separate route tables for segmentation. Attachments reuse the workload private subnets; AWS recommends a dedicated /28 per AZ so workload NACLs don't affect TGW traffic. Spoke B has one AZ, so its attachment only serves that AZ.

Evidence: [TGW](../evidence/week2/w2-2.4-console-tgw-available.png) · [attachments](../evidence/week2/w2-2.4-console-tgw-attachments.png) · [TGW routes](../evidence/week2/w2-2.4-console-tgw-rt-propagated.png) · [Spoke B routes](../evidence/week2/w2-2.4-console-spoke-b-rt-tgw.png) · [hub private routes](../evidence/week2/w2-2.4-console-hub-private-rt-tgw.png) · [Spoke B attachment subnet](../evidence/week2/w2-2.4-console-tgw-att-spoke-b-subnet.png)

**Step 4: test instances + SSM endpoints (option B).** `lab-spoke-a-ec2` (10.1.1.239, profile `secnet-ec2-profile`) and `lab-spoke-b-ec2` (10.2.1.191 after relaunch, **no IAM role**), AL2023 t3.micro, no key pair, no public IP, IMDSv2, Python web server on :80. Three interface endpoints in Spoke A only (`ssm`, `ssmmessages`, `ec2messages`, private DNS on, SG `lab-spoke-a-vpce-sg` 443 from 10.1.0.0/16). Spoke B has no endpoints and no NAT, so it cannot reach SSM or any AWS API — shown as "Not connected". Instance SGs allow ICMP + 80 from 10.0.0.0/8 so that failed spoke-to-spoke tests are caused by routing, not SGs.

Evidence: [SGs](../evidence/week2/w2-2.5-console-lab-sgs.png) · [endpoints](../evidence/week2/w2-2.5-console-spoke-a-ssm-endpoints.png) · [Spoke A session](../evidence/week2/w2-2.5-console-spoke-a-ssm-session.png) · [Spoke B no SSM](../evidence/week2/w2-2.5-console-spoke-b-no-ssm.png) · [DNS A](../evidence/week2/w2-2.5-console-spoke-a-dns.png) · [DNS B](../evidence/week2/w2-2.5-console-spoke-b-dns.png)

**Step 5: PrivateLink (Spoke B service → hub).** Provider (Spoke B): target group `lab-tg-spoke-b` (TCP 80, 1 healthy), internal NLB `lab-nlb-spoke-b` with SG `lab-nlb-spoke-b-sg` (TCP 80 from 10.0.0.0/8, attached at creation), endpoint service `lab-svc-spoke-b` (vpce-svc-071528d8674a0de35, **acceptance required**). Consumer (hub): interface endpoint `lab-vpce-hub-to-spoke-b` (vpce-0064eeef049ece393, ENI 10.0.11.235 in secnet-private-1, SG `lab-hub-vpce-svc-sg` 80 from 10.0.0.0/16), accepted by the provider. Unlike peering/TGW, only one service on one port is exposed and no routes are needed.

Evidence: [NLB](../evidence/week2/w2-2.7-console-nlb-active.png) · [target healthy](../evidence/week2/w2-2.7-console-nlb-target-healthy.png) · [endpoint service](../evidence/week2/w2-2.7-console-endpoint-service.png) · [hub endpoint](../evidence/week2/w2-2.7-console-hub-endpoint-available.png) · [test run 1](../evidence/week2/w2-2.7-console-privatelink-test-run1.png) · [ports run 2](../evidence/week2/w2-2.7-console-privatelink-ports-run2.png)

**Step 7: cleanup.** All `lab-*` resources deleted in dependency order (PrivateLink consumer → provider → NLB/TG; instances; endpoints; hub manual routes; TGW attachments → TGW; peering; SGs; spoke VPCs). Verified by CLI: only `secnet-vpc` and the default VPC remain, `secnet-private-rt` is back to `local` + NAT, TGW deleted, no VPC endpoints, only `secnet-alb`. [Evidence](../evidence/week2/w2-2.8-console-cleanup-verified.png)

## Tests (command · expected · actual)

| # | Command | Expected | Actual | Screenshot |
|---|---|---|---|---|
| 2.6-1 | Hub web → Spoke A: `curl http://10.1.1.239` | `hello from lab-spoke-a` (peering) | ✅ as expected | [hub run 1](../evidence/week2/w2-2.6-console-tests-from-hub-run1.png) |
| 2.6-2 | Hub web → Spoke A: `ping 10.1.1.239` | FAIL: hub NACL drops the ICMP reply from 10.1.0.0/16 | ✅ FAIL as expected | same |
| 2.6-3 | Hub web → Spoke B: `curl http://10.2.1.150` | `hello from lab-spoke-b` (TGW) | ⚠️ reply received, so the TGW path works, but the text said `lab-spoke-a`: Spoke B was launched with Spoke A's user data. Relaunched (new IP 10.2.1.191): ✅ `hello from lab-spoke-b` | run 1 + [hub run 2](../evidence/week2/w2-2.6-console-tests-from-hub-run2.png) |
| 2.6-4 | Hub web → Spoke B: `ping 10.2.1.150` (run 2: 10.2.1.191) | FAIL (same NACL reason as 2.6-2) | ❌ **ping OK in both runs — prediction wrong**. Likely cause: the TGW attachment ENI sits in the same subnet as the web instance, so the hub NACL isn't evaluated for TGW → instance traffic. AWS docs ([TGW network ACLs](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-nacls.html)): when instances and the attachment share a subnet, NACL rules are **not evaluated** for traffic from the TGW to the instances. So the hub NACL is bypassed for TGW traffic: a security finding, fixed by dedicated /28 TGW subnets. **Confirmed:** `lab-tgw-att-hub` uses subnet-0f0d98ce4532b1adb (`secnet-private-1`, same subnet as the web instance 10.0.11.167) and subnet-0e8689dbe4d04a8a6 (`secnet-private-2`) — [evidence](../evidence/week2/w2-2.6-console-tgw-att-hub-subnets.png) | same |
| 2.6-5 | Spoke A → hub web: `ping 10.0.11.167` | FAIL: hub NACL inbound ICMP | ✅ FAIL | [spoke A](../evidence/week2/w2-2.6-console-tests-from-spoke-a.png) |
| 2.6-6 | Spoke A → hub web: `curl http://10.0.11.167` | FAIL: NACL (only 1024–65535 from outside) + web SG (80 from ALB only) | ✅ FAIL | same |
| 2.6-7 | Spoke A → Spoke B: ping + curl 10.2.1.150 | FAIL: peering is not transitive (no route); Spoke B SG allows 10.0.0.0/8 | ✅ FAIL | same |
| 2.6-8 | Spoke A: `getent hosts ssm.eu-west-1.amazonaws.com` | private 10.1.1.x (endpoint private DNS) | ✅ 10.1.1.143 | same |
| 2.6-9 | Spoke A → internet: `curl https://aws.amazon.com` | `000` / FAIL (no IGW/NAT) | ✅ 000 | same |
| 2.7-1 | Hub web: `getent hosts <PrivateLink endpoint DNS>` | private hub IP (endpoint ENI in secnet-vpc) | ✅ 10.0.11.235 | [PrivateLink run 1](../evidence/week2/w2-2.7-console-privatelink-test-run1.png) |
| 2.7-2 | Hub web → `curl http://<endpoint DNS>` | `hello from lab-spoke-b` via endpoint → NLB → Spoke B | ✅ as expected | same |
| 2.7-3 | Hub web → endpoint port 22 | timeout: only TCP 80 is published | ⚠️ run 1 invalid: `curl telnet://` returned exit 1 (*unsupported protocol*, AL2023 ships `curl-minimal`). Run 2 with bash `/dev/tcp` (port 80 as control): ✅ `port 80 OPEN`, `port 22 CLOSED (exit=124)` | [ports run 2](../evidence/week2/w2-2.7-console-privatelink-ports-run2.png) |
| 2.5-1 | Spoke A: Session Manager | connects via the 3 interface endpoints | ✅ `10.1.1.239`, `hello from lab-spoke-a` | [session](../evidence/week2/w2-2.5-console-spoke-a-ssm-session.png) |
| 2.5-2 | Spoke B: Session Manager | not connected (no endpoints, no NAT, no role) | ✅ "Not connected", agent can't get credentials | [spoke B](../evidence/week2/w2-2.5-console-spoke-b-no-ssm.png) |

## Problems and how we fixed them

- **2026-10-18, end of session: grep on the wrong file.** A `terraform -chdir=terraform/envs/dev …` command run from inside `envs/dev` failed (`chdir … no such file or directory`) and `tee` saved the error into `envs/dev/destroy.txt`. A later safety grep on that file returned nothing, which looked like a pass. The real plan output was in the repo-root `destroy.txt` and was checked separately (23 to destroy, nothing protected). Rule: run `-chdir` commands from the repo root, and `ls -la` the file you grep to confirm its time and size.

- **2026-10-18, console step 5 (PrivateLink): NLB creation blocked by AWS.** Creating `lab-nlb-spoke-b` failed with `OperationNotPermittedException: This AWS account currently does not support creating load balancers` ([evidence](../evidence/week2/w2-2.7-console-nlb-blocked.png)). This is an account-level restriction set by AWS, not an IAM or quota problem: the Terraform ALB `secnet-alb` was created in the same account earlier the same day. AWS re:Post answers link it to accounts without enough billing history to be auto-approved for ELB. **Resolved the same day:** a later attempt to create the NLB succeeded, so no support case was needed. The block was temporary; we keep the open item to re-test load balancer creation before the 2 Nov demo.
- **2026-10-18, console step 4: Spoke B launched with Spoke A's user data** (answered `hello from lab-spoke-a`). User data only runs on first boot, so the instance was terminated and relaunched with the correct script (new IP 10.2.1.191).

## Cost and cleanup

Hours with each switch on, Cost Explorer screenshot, `make sleep` runs.

## Open items

- [ ] Demo risk: ELB creation was briefly blocked on 2026-10-18 (`OperationNotPermittedException`, worked on retry). Run the Terraform rebuild at least a day before the 2 Nov demo; if the block returns, open an AWS Support (Account and billing) case at once.
- [ ] Terraform gap found 2026-10-18: `modules/connectivity` builds spokes, peering, TGW and VPN but **no SSM interface endpoints, no S3 gateway endpoint, no PrivateLink (NLB + endpoint service) and no spoke test instances**. Code needed before the Terraform build (step 8).
- [x] Before step 8: delete the manual console routes on `secnet-private-rt` (done 2026-10-18, verified) (10.1.0.0/16, 10.2.0.0/16). Terraform manages these as separate `aws_route` resources, so it won't detect them; it will fail with RouteAlreadyExists if they're still there.
- [ ] Architecture diagram (`docs/architecture/architecture.py`): show the private subnets inside Spoke A (10.1.1.0/24) and Spoke B (10.2.1.0/24), and that the spokes have no IGW/NAT. Raised by Alber 2026-10-18.
