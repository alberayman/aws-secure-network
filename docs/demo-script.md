# Demo script (live demo ~27–28 Nov, final presentation 4 Dec)

Draft from the 21–22 Nov rehearsal. Times are minutes from the start of the demo.
Everything is run from the repo root (`aws-secure-network %`). All IDs/IPs/URLs come from `terraform output`.

## 30 minutes before

| # | Do | Expected |
|---|---|---|
| 1 | `terraform -chdir=terraform/envs/dev plan -out=tf.plan` → review → apply (or confirm the stack is already up) | `isolate_victim = false` in tfvars |
| 2 | Confirm the new **WAF SNS email** (`secnet-alerts`, us-east-1) | "Subscription confirmed!" |
| 3 | `make vpn-setup` | tunnel1 ESTABLISHED · ping OK · AWS 1 UP |
| 4 | `make demo ARGS="--auto"` (smoke test) | 35 passed, T39 skipped |
| 5 | Open in browser tabs: website (`output -raw cloudfront_url`), app (`output -raw app_url`), GuardDuty findings, CloudWatch alarms, Athena (workgroup `secnet`), email inbox | – |
| 6 | Have rehearsal evidence ready: `docs/evidence/week4/w4-T3*`, `docs/incidents/IR-001-timeline.md` | fallback |
| 7 | Open **two terminals, both in the repo folder** (`cd ~/Projects/DEPI/aws-secure-network`), `export AWS_PROFILE=secnet` in each | prompt ends `aws-secure-network %` |
| 8 | Archive old GuardDuty findings so only the live one shows: `D=$(terraform -chdir=terraform/envs/dev output -raw guardduty_detector_id); aws guardduty archive-findings --detector-id "$D" --finding-ids $(aws guardduty list-findings --detector-id "$D" --query FindingIds --output text)` | GuardDuty Findings list empty |

**Expected noise:** `secnet-hub-ssh-attempt` fires ~5 min after any full test run, because test **T21** probes
port 22 on the PrivateLink endpoint (blocked, but counted). Not an incident: rule it out by time and source IP
(the web server) – that is the first triage step in the runbook.

## Running order (≈28 min, tests in --auto)

| Min | What you show | Command / screen | Running in the background |
|---|---|---|---|
| 0–2 | Problem + "a server has just been compromised; we will come back to it" | `make ir-simulate ARGS=--auto` | attack traffic; timeline written |
| 2–5 | Architecture + traffic-flow diagrams; the website itself is served by the edge we built | website tab | alarms fire at ~min 3–4 |
| 5–12 | **Full project test, live:** `make demo ARGS="--auto"` (all 35 tests in ≈4 min; talk over the output: point at *Proves*, the ❌ = "blocked is what we want", and the summary). Interactive `make demo` only if the slot is ≥ 40 min | terminal 2 | alarms ~min 1–3, GuardDuty ~min 3 |
| 12–17 | **Detect:** alarm emails (3) + GuardDuty email (sev 8, victim instance ID) | inbox, GuardDuty console | – |
| 17–21 | **Investigate:** Athena saved query **15** (replace X with `output -raw victim_private_ip`) | Athena | – |
| 21–23 | **Preserve:** evidence snapshot with tags `Case=IR-001`, `Phase=pre-containment` | CLI (runbook) | – |
| 23–26 | **Contain:** `sed -i '' 's/^isolate_victim *= *false/isolate_victim   = true/' terraform/envs/dev/terraform.tfvars` → `make plan` → **read the plan line aloud** ("0 to add, 2 to change, 0 to destroy: only the victim's SG and the NACL; approved") → `make apply` → `make demo ARGS="--only T39"` | terminal 1 | – |
| 26–28 | **Audit + lessons:** CloudTrail events; lessons table; production next steps | CloudTrail, runbook | – |

During the full run, **T39 shows SKIP** (the victim is not isolated yet); it is run on its own after containment.
The full run also triggers the `secnet-hub-ssh-attempt` alarm (T21 probes port 22): point it out as the
"rule out your own activity" triage step, next to the real IR-001 alarms (Spoke A rejected flows, GuardDuty).

After the demo: `sed -i '' 's/^isolate_victim *= *true/isolate_victim   = false/' terraform/envs/dev/terraform.tfvars` (**always** – otherwise the next build creates the victim already isolated), then `make sleep`.

**Rehearsal 2026-11-22:** all phases passed; total 30–40 min with interactive tests → Phase 3 now uses `--auto`.
Detection: Spoke A SSH alarm +25 s, rejected-flows +1 min, hub SSH +1.5 min, GuardDuty +2.5 min after the attack ended.

## Fallbacks

| If | Then |
|---|---|
| GuardDuty finding not there yet | say "GuardDuty batches DNS analysis"; show rehearsal finding `w4-T36-guardduty-real-finding-email.png`; point out the live email if it arrives later |
| Athena returns nothing | flow logs reach S3 every ~10 min: use CloudWatch Logs Insights (dashboard queries `top_rejects`, `port_scan`) on the 1-minute logs |
| VPN test fails | `make vpn-setup` again (≈2 min); fallback evidence `w2-2.12-vpn-*.png` |
| Anything else breaks | rehearsal evidence for that step in `docs/evidence/` |

## Likely questions

- Why both peering and Transit Gateway? – To compare them; production standardises on TGW.
- Is it 3-tier? – Yes at network level: public (ALB), private app (EC2), isolated data (RDS), each behind its own SG + NACL.
- Why ACCEPT rows in Athena during the scan? – Flow logs are per interface: ACCEPT where it left the victim, REJECT where Spoke A dropped it.
- Why HTTP from CloudFront to the ALB? – No domain/certificate in the lab (D8); production: ACM cert or VPC origins.
- What would you do differently? – See "Production next steps" (single-AZ parts, one role per workload, Network Firewall, log-archive account).
