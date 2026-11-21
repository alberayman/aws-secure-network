# Plan to the final presentation

Decided 2026-11-17 by Alber. **Demo: ~27–28 Nov 2026 · Final presentation: 4 Dec 2026.**
Approach from now on: **Terraform-first** – Terraform builds it, then we walk through every
resource in the console together and take the screenshots. Daily sessions of 2–3 hours.
Every session ends with a verified teardown (hub baseline only: VPC, CloudTrail, logs, alarms, budget).

| Date | Session | Goal | Demo tests |
|---|---|---|---|
| Sat 21 Nov | 1 | Code only (no AWS cost): fix the 4 Week 2 open items – PrivateLink accept wait, AMI drift, `enable_compute` switch so `make sleep` is one normal plan (fixes the monitoring coupling and the teardown order) | `make check`; sleep plan = No changes |
| Sun 22 Nov | 2 | Build hybrid + Site-to-Site VPN with **TGW route tables for segmentation**; the rebuild also proves Session 1's fixes; `make sleep` | T14–T21b, T17, T18, T26 |
| Mon 23 Nov | 3 | Week 3 edge: CloudFront + private S3 (OAC) + WAF + Route 53 private zone | T27–T30+ |
| Tue 24 Nov | 4 | Week 4: Flow Logs + Athena, scan alarm drill, CloudTrail investigation, victim evidence snapshot + quarantine | Week 4 |
| Wed 25 Nov | 5 | Final report, presentation deck, demo script, demo-test-plan complete; repo visibility for judges | – |
| Thu 26 Nov | 6 | **Dress rehearsal:** rebuild everything from zero (timed), whole demo test list, `make sleep` | all |
| Fri 27 Nov | – | Buffer / demo day | – |
| 28 Nov–3 Dec | – | Fix demo feedback, final rehearsal on 3 Dec | – |
| Fri 4 Dec | – | Final presentation | – |

**Re-planned 2026-11-21** after 18–20 Nov were lost: **Client VPN** and **Traffic Mirroring** are now
design-only (documented in the report, code kept but not applied); the Client VPN/docs session was folded
into Sessions 2 and 5.

## Risks and how we handle them

| Risk | Mitigation |
|---|---|
| A session slips | Client VPN and Traffic Mirroring already cut; next to cut: Route 53 health check, Week 3 WAF logging |
| Long build times on demo day (RDS ≈ 8 min, CloudFront ≈ 5–15 min, VPN + strongSwan config) | Timed rebuild in the dress rehearsal; on demo day build ≥ 1 h before |
| ELB creation briefly blocked by AWS (seen 2026-10-18) | Dress rehearsal 26 Nov leaves time to open an AWS Support case |
| Cost of daily builds (≈ $0.4–0.6/h while up) | Build only for the session, verified teardown every time; budget alerts track gross cost |
| Office-to-Spoke-B segmentation (T18) fails with the current single TGW route table | Session 2 adds separate TGW route tables (also closes the "one routing domain" trade-off from the console lab) |
