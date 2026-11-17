# Plan to the final presentation

Decided 2026-11-17 by Alber. **Demo: ~27–28 Nov 2026 · Final presentation: 4 Dec 2026.**
Approach from now on: **Terraform-first** – Terraform builds it, then we walk through every
resource in the console together and take the screenshots. Daily sessions of 2–3 hours.
Every session ends with a verified teardown (hub baseline only: VPC, CloudTrail, logs, alarms, budget).

| Date | Session | Goal | Demo tests |
|---|---|---|---|
| Wed 18 Nov | 1 | Fix the 4 Week 2 open items in code (PrivateLink accepter race, AMI drift, spoke/hub monitoring split, teardown order); full Week 2 rebuild from zero proves the fixes, clean teardown | T14–T21b re-run |
| Thu 19 Nov | 2 | Site-to-Site VPN: strongSwan office + TGW VPN attachment; **TGW route tables for segmentation** (office must not reach Spoke B) | T17, T18, T26 |
| Fri 20 Nov | 3 | Client VPN (mutual TLS) + Week 2 docs: route tables, Direct Connect design, architecture diagram update (spoke subnets, TGW /28s, VPN) | T22–T25 |
| Sat 21 Nov | 4 | Week 3 edge: CloudFront + private S3 (OAC) + WAF | T27–T30+ |
| Sun 22 Nov | 5 | Week 3: Route 53 private zone, WAF logging/metrics, Week 3 docs | Week 3 rest |
| Mon 23 Nov | 6 | Week 4 detection: Flow Logs + Athena, internal-scan alarm drill, CloudTrail investigation | Week 4 detection |
| Tue 24 Nov | 7 | Week 4 incident response: victim instance, evidence snapshot, quarantine SG, runbook drill (traffic mirroring only if time allows) | Week 4 IR |
| Wed 25 Nov | 8 | Final report, presentation deck, demo script, demo-test-plan complete; repo visibility for judges | – |
| Thu 26 Nov | 9 | **Dress rehearsal:** rebuild everything from zero (timed), run the whole demo test list, teardown | all |
| Fri 27 Nov | – | Buffer / demo day | – |
| 28 Nov–3 Dec | – | Fix demo feedback, final rehearsal on 3 Dec | – |
| Fri 4 Dec | – | Final presentation | – |

## Risks and how we handle them

| Risk | Mitigation |
|---|---|
| A session slips | Week 4 traffic mirroring and Client VPN are the first things to cut (documented as design-only) |
| Long build times on demo day (RDS ≈ 8 min, CloudFront ≈ 5–15 min, VPN + strongSwan config) | Timed rebuild in the dress rehearsal; on demo day build ≥ 1 h before |
| ELB creation briefly blocked by AWS (seen 2026-10-18) | Dress rehearsal 26 Nov leaves time to open an AWS Support case |
| Cost of daily builds (≈ $0.4–0.6/h while up) | Build only for the session, verified teardown every time; budget alerts track gross cost |
| Office-to-Spoke-B segmentation (T18) fails with the current single TGW route table | Session 2 adds separate TGW route tables (also closes the "one routing domain" trade-off from the console lab) |
