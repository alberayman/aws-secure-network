# Incident response runbook: compromised EC2 instance (case IR-001)

Owner: Member 5 (with Member 4 for containment). Steps and commands: Guide 4.
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
| EBS snapshot (pre-containment) | snap- | n/a (AWS-managed) | | | EC2 snapshots, tag Case=IR-001 | |
| Flow log query export | | | | | s3://secnet-logs-…/evidence/ | |
| CloudTrail export | | | | | | |
| Mirrored pcap | ir-001.pcap | | | | | |

## Lessons learned

| Finding | Fix | Owner | Due |
|---|---|---|---|
| Web and victim share one IAM role | one role per workload | | |
