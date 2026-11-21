# Incident response runbook: compromised EC2 instance (case IR-001)

Owner: Member 5 – Ahmed (with Member 4 – Asmaa for containment). Steps and commands: Guide 4.
All times in **UTC**.

| Phase | Who | What | How (console / CLI) | Evidence produced |
|---|---|---|---|---|
| 1. Detect | | alarm or Athena hit | saved queries 10–14, WAF alarm | query result CSV + hash |
| 2. Triage | | real? which host? severity? | instance tags, SG, CloudTrail | triage note |
| 3. Preserve | | EBS snapshot, export logs, pcap | `aws ec2 create-snapshot …` | snapshot ID, SHA-256 of exports |
| 4. Contain | | quarantine SG, revoke role sessions, tag, keep running | `modify-instance-attribute`, IAM *Revoke active sessions* | CloudTrail events |
| 5. Eradicate & recover | | rebuild from code, rotate secrets | `terraform apply -replace='aws_instance.victim[0]'` | new instance ID |
| 6. Lessons learned | all | fixes with owner + date | review meeting | lessons table |

## Timeline

| Time (UTC) | Event | Source | By |
|---|---|---|---|
| T0 | simulation starts | Member 2 notes | |
| | | | |

## Chain of custody

| Item | ID / file | SHA-256 | Collected by | Collected at (UTC) | Stored at | Accessed by |
|---|---|---|---|---|---|---|
| EBS snapshot (pre-containment) | snap-055cac4e403b6e6d9 (vol of i-07766341a79b8bedb) | n/a (AWS-managed) | Alber (secnet-lab) | 2026-11-21 20:42:02 | EC2 snapshots, tags Case=IR-001, Phase=pre-containment | |
| Flow log query export | | | | | s3://secnet-logs-…/evidence/ | |
| CloudTrail export | | | | | | |
| Mirrored pcap | ir-001.pcap | | | | | |

## Lessons learned

| Finding (IR-001 rehearsal, 2026-11-21) | Fix | Status |
|---|---|---|
| Web and victim share one IAM role: revoking the victim's sessions would also cut the web server | One role per workload; then "Revoke active sessions" is safe in containment | Production recommendation |
| A security group swap does not cut connections that are already tracked | NACL deny in/out for the host /32 added to containment (stateless) | **Done** (isolate_victim) |
| After isolation SSM cannot reach the victim, so no live forensics (processes, memory) | Collect volatile data before containment, or let the quarantine SG reach SSM interface endpoints only | Production recommendation |
| The SG swap is logged on the network interface, not the instance (`ModifyNetworkInterfaceAttribute`) | Search CloudTrail by event name / ENI ID; added to this runbook | **Done** |
| Alarms return to OK ≈5 min after the activity stops | Triage from alarm emails / alarm history; GuardDuty finding stays open | Documented (demo script) |
| Host-timeline query too broad (625 rows, boot traffic first) | Saved query 15 "victim lateral movement" (+ interface_id to show source ACCEPT vs target REJECT) | To add |
| Plan shows inline NACL rules as remove/re-add (API only created the 2 deny entries) | Separate `aws_network_acl_rule` resources for readable plans | Production recommendation |
| Evidence snapshot lives outside Terraform (on purpose) | Delete by hand when the case is closed (clean-up checklist) | Open |
