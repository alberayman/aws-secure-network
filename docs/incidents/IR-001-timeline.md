# IR-001 timeline (UTC)

| Time (UTC) | Event | Source | By |
|---|---|---|---|
| 2026-11-21 20:12:17 | T0 – simulation starts on i-07766341a79b8bedb (10.0.11.222) | ir-simulate.sh | simulation script |
| 2026-11-21 20:12:47 | Step 1 – port scan of Spoke A 10.1.1.46 (~80 ports) | ir-simulate.sh | simulation script |
| 2026-11-21 20:13:24 | Step 2 – 10 SSH attempts to 10.1.1.46:22 | ir-simulate.sh | simulation script |
| 2026-11-21 20:14:04 | Step 3 – DNS lookups of guarddutyc2activityb.com (C2 test domain) | ir-simulate.sh | simulation script |
| 2026-11-21 20:14:22 | Step 4 – lookup of c2.evil-demo.example (blocklisted) | ir-simulate.sh | simulation script |
| 2026-11-21 20:13:53 | DETECT – alarm secnet-spoke_a-rejected-flows-spike → ALARM (80 rejected flows in 5 min) → email | CloudWatch / SNS | automatic |
| 2026-11-21 20:13:56 | DETECT – alarm secnet-hub-ssh-attempt → ALARM (victim's outbound port 22 seen in the hub too) → email | CloudWatch / SNS | automatic |
| 2026-11-21 20:14:01 | DETECT – alarm secnet-spoke_a-ssh-attempt → ALARM (11 SSH flows) → email | CloudWatch / SNS | automatic |
| 2026-11-21 20:17 | DETECT – GuardDuty Backdoor:EC2/C&CActivity.B!DNS, severity 8, on i-07766341a79b8bedb → EventBridge → email | GuardDuty / SNS | automatic |
| 2026-11-21 20:18:53 | alarms return to OK by themselves (activity stopped) – the finding stays open | CloudWatch | automatic |
| 2026-11-21 ~20:30 | INVESTIGATE – Athena 12: 10.0.11.222 → 10.1.1.46, 80 distinct ports REJECTed (top result); Athena 14: victim timeline (625 flows, boot traffic from 20:07 then the scan) | Athena (S3 flow logs) | Alber |
| 2026-11-21 20:42:02 | PRESERVE – evidence snapshot snap-055cac4e403b6e6d9 of the victim root volume, tags Case=IR-001, Phase=pre-containment (outside Terraform on purpose) | EC2 CreateSnapshot | Alber |
| 2026-11-21 20:47:45 | CONTAIN – terraform apply (isolate_victim = true): victim tagged Status=Quarantined (CloudTrail CreateTags by secnet-lab), SG → secnet-isolation, NACL deny rule 10 in/out for 10.0.11.222/32 | Terraform / CloudTrail | Alber |
| 2026-11-21 20:48 | VERIFY – T39 PASS: SG secnet-isolation · 2 NACL deny rules · web→victim ping FAIL · website 200 | demo-tests.sh | Alber |
| 2026-11-21 20:47:46 | AUDIT – CloudTrail ModifyNetworkInterfaceAttribute (SG swap on the victim ENI) by secnet-lab | CloudTrail | automatic |
| 2026-11-21 20:47:48 | AUDIT – CloudTrail 2 × CreateNetworkAclEntry (deny in/out 10.0.11.222/32) by secnet-lab; no delete/replace of other entries | CloudTrail | automatic |
| 2026-11-21 ~21:02 | RECOVER – rebuilt from code (terraform -replace): infected i-07766341a79b8bedb terminated, clean victim i-04426521c680d305b (10.0.11.85), NACL deny rules removed, new baseline snapshot | Terraform | Alber |
| 2026-11-21 ~21:03 | VERIFY – evidence snapshot snap-055cac4e403b6e6d9 completed, tag Phase=pre-containment, kept; old instance terminated | EC2 API | Alber |
| 2026-11-22 14:13:52 | T0 – simulation starts on i-07d67ea22646f04ba (10.0.11.102) | ir-simulate.sh | simulation script |
| 2026-11-22 14:13:57 | Step 1 – port scan of Spoke A 10.1.1.34 (~80 ports) | ir-simulate.sh | simulation script |
| 2026-11-22 14:14:20 | Step 2 – 10 SSH attempts to 10.1.1.34:22 | ir-simulate.sh | simulation script |
| 2026-11-22 14:14:24 | Step 3 – DNS lookups of guarddutyc2activityb.com (C2 test domain) | ir-simulate.sh | simulation script |
| 2026-11-22 14:14:29 | Step 4 – lookup of c2.evil-demo.example (blocklisted) | ir-simulate.sh | simulation script |
