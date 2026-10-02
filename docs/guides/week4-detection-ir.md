# Week 4: Network monitoring, detection and incident response (step by step)

**Goal:** run a full incident drill. Simulate a compromised instance, detect it from logs, contain it without destroying evidence, collect and hash the evidence, and write it up.
**Gate to pass:**
- the Athena queries show the simulated activity;
- the victim is isolated (REJECT lines afterwards);
- the timeline matches the CloudTrail events;
- the runbook and final report are complete.

**Safety rule for the whole week:** every "attack" runs **only from our own victim instance, against our own addresses, in our own AWS account**. Nothing targets anything outside the account.

| Task | Member | Terraform files | Switch |
|---|---|---|---|
| 4.1 Victim + simulation + evidence snapshots | 2 | `envs/dev/victim.tf` | `enable_ir` |
| 4.2 Traffic Mirroring | 3 | `envs/dev/mirroring.tf` | `enable_mirroring` |
| 4.3 Containment | 4 | `envs/dev/isolation.tf` | `isolate_victim` |
| 4.4 Athena, detections, runbook, CloudTrail evidence | 5 | `modules/monitoring/athena.tf` | automatic |
| 4.4b CloudWatch network detection (alarms, Logs Insights, dashboard) | 5 | `modules/monitoring/cloudwatch.tf` | automatic |
| 4.5 Final report, presentation, cleanup | 6 | - | all off |

**Drill order** (agree on a start time and write down every timestamp in UTC):
**prepare** (4.2 mirroring on, 4.4 table created) → **simulate** (4.1) → **detect** (4.4) → **preserve** (4.1 snapshot) → **contain** (4.3) → **verify and collect** (4.4) → **write up** (4.4, 4.5).

Set `enable_hybrid = true` for the drill: the victim scans the Spoke A test instance.

---

## 4.1 Member 2: the victim and the simulation

### Console steps
1. Launch `secnet-victim`: Amazon Linux 2023, `t3.micro`, hub **private** subnet 1, SG `secnet-ec2-sg`, profile `secnet-ec2-profile`, IMDSv2, encrypted disk. Tags `Case=IR-001`. Keep `secnet-web` untouched so the website stays up.
2. Write down **T0** (start). In Session Manager on the victim, run harmless but suspicious-looking activity:
```bash
# 1. Antivirus test file: harmless by design, every scanner recognises it
curl -s -o /tmp/eicar.com.txt https://secure.eicar.org/eicar.com.txt
# 2. Port sweep of OUR Spoke A test instance (its SG only allows ICMP + 80, so most attempts are REJECTed)
for p in 21 22 23 25 110 135 139 445 1433 3306 3389 5432 5900 6379 8080; do timeout 1 bash -c "echo > /dev/tcp/10.1.1.X/$p" 2>/dev/null; done
# 3. Repeated SSH attempts (port 22 should never appear in this design)
for i in $(seq 1 40); do timeout 1 bash -c "echo > /dev/tcp/10.1.1.X/22" 2>/dev/null; done
# 4. Odd outbound: unusual destination port on the internet
for i in $(seq 1 20); do curl -s -m 2 http://example.com:8080 >/dev/null; done
```
Replace `10.1.1.X` with `terraform output spoke_test_ips` → `a`. Write down **T1** (end).

3. **Evidence snapshot, BEFORE containment:** **EC2** > Instances > `secnet-victim` > **Storage** tab > volume ID > **Actions** > **Create snapshot**. Description `evidence-secnet-victim-<UTC time>`, tags `Case=IR-001`, `Collected-by=<your name>`, `Phase=pre-containment`. Or from the CLI:
```bash
VOL=$(aws ec2 describe-instances --instance-ids <victim_id> --query "Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId" --output text)
aws ec2 create-snapshot --volume-id $VOL --description "evidence-secnet-victim-$(date -u +%Y%m%dT%H%MZ)" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Case,Value=IR-001},{Key=Collected-by,Value=<name>},{Key=Phase,Value=pre-containment}]"
```
4. Take a second snapshot **after** containment (`Phase=post-containment`).
5. Write `docs/week4/incident-scenario.md`: what you ran, command by command, T0/T1, and which detections you expect.

Optional: **GuardDuty** (30-day free trial). Enable it, then **Settings** > **Generate sample findings** to see what real detections look like. Disable it after the drill.

### Terraform (`envs/dev/victim.tf`)
- `aws_instance.victim`: its SG is chosen by `var.isolate_victim`, and its `Status` tag flips to `Quarantined`.
- `aws_ebs_snapshot.baseline` is a "known good" snapshot taken at creation. The real evidence snapshots are the manual ones above, because they must capture the system **at the moment of the incident**.

```bash
# terraform.tfvars: enable_hybrid = true, enable_ir = true
terraform plan -out w4.tfplan && terraform apply w4.tfplan
terraform output victim_instance_id victim_private_ip
```

---

## 4.2 Member 3: Traffic Mirroring

Flow Logs record **metadata** (who, to whom, port, bytes, accept/reject). Traffic Mirroring copies the **full packets** from an ENI to a target, wrapped in VXLAN on UDP 4789. It only works on Nitro instances (`t3` qualifies).

### Console steps
1. Launch `secnet-mirror-target`: Ubuntu 22.04, `t3.micro`, hub private subnet, profile `secnet-ec2-profile`, new SG `secnet-mirror-sg` with inbound **UDP 4789 from `10.0.0.0/16`**. User data: `apt-get update && apt-get install -y tcpdump suricata`.
2. **VPC** > **Traffic Mirroring** > **Mirror targets** > Create: type *Network interface*, the target's ENI.
3. **Mirror filters** > Create `secnet-all`: inbound rule 100 *accept*, all protocols, `0.0.0.0/0` → `0.0.0.0/0`. Outbound rule 100, the same.
4. **Mirror sessions** > Create: source = the **victim's** ENI, target = the mirror target, filter `secnet-all`, session number 1.
5. Re-run the 4.1 commands on the victim. On the target:
```bash
sudo tcpdump -i ens5 -nn udp port 4789 -c 200 -w /tmp/ir-001.pcap     # capture
sudo tcpdump -nn -r /tmp/ir-001.pcap | head -30                       # read it back
sha256sum /tmp/ir-001.pcap                                             # record the hash
sudo suricata -r /tmp/ir-001.pcap -l /tmp/suri && cat /tmp/suri/fast.log   # rule hits (none is fine, record it)
```
6. Copy a **small** sample (a few KB, no credentials) to `docs/evidence/week4/`. Then **delete the session, target, filter and instance**.
7. Write `docs/week4/traffic-mirroring.md`: why mirroring, what you captured, how it differs from Flow Logs, and the cost.

### Terraform (`envs/dev/mirroring.tf`)
Everything is gated by `enable_ir && enable_mirroring`: the Ubuntu target with tcpdump + Suricata, `aws_ec2_traffic_mirror_target`, a filter with two accept-all rules (`for_each` over ingress/egress), and `aws_ec2_traffic_mirror_session.victim`.
```bash
# enable_mirroring = true → apply → capture → enable_mirroring = false → apply
```

---

## 4.3 Member 4: containment

Containment cuts the attacker off **without destroying evidence**. Do the steps in this order and timestamp each one.

### Console steps
1. **Preserve first:** confirm that the pre-containment snapshot from 4.1 is `completed`.
2. **Quarantine SG:** **EC2** > Security groups > Create `secnet-isolation` in `secnet-vpc`. **No inbound rules. Delete the default outbound "All traffic" rule**, so there are none.
3. **Swap groups:** `secnet-victim` > **Actions** > **Security** > **Change security groups**. Remove `secnet-ec2-sg`, add only `secnet-isolation`, Save.
   SGs are stateful, so connections that are already open can survive for a while. For a hard cut you can also put the subnet behind a deny NACL. Note the trade-off: that affects every host in the subnet.
4. **Cut the credentials:** **IAM** > Roles > `secnet-ec2-role` > **Revoke active sessions**. This denies any token issued before now, including tokens stolen from IMDS.
   - The role is shared with `secnet-web`, so this breaks the web server's SSM session too. Real-world fix: **one role per workload**. Write it as a hardening finding.
5. **Tag it:** `Status=Quarantined`, `Case=IR-001`. **Do not terminate it**: terminating destroys the memory and disk evidence.
6. **Verify isolation:**
   - From the web host, `ping` and `curl` the victim. Both must fail.
   - Session Manager to the victim no longer connects (expected: it cannot reach SSM any more).
   - Later, Flow Logs show `REJECT` lines to and from the victim.
7. Write `docs/week4/containment-checklist.md`: numbered steps, who does each one, how to verify, and the time taken.
8. **Hardening recommendations**:
   - restrict egress (only 443 to VPC endpoints, 3306 to RDS);
   - one IAM role per instance;
   - GuardDuty + EventBridge auto-isolation;
   - VPC endpoints instead of NAT;
   - an alarm on REJECT spikes.

### Terraform (`envs/dev/isolation.tf` + `victim.tf`)
`aws_security_group.isolation` declares no rules, so Terraform also removes AWS's default allow-all egress rule. To contain through code (a repeatable drill):
```bash
terraform apply -var isolate_victim=true      # swaps the SG and sets Status=Quarantined
```
In a real incident you would use the console or CLI for speed (`aws ec2 modify-instance-attribute --instance-id <id> --groups <sg-isolation>`). Code is how you document and rehearse it.

### Check it worked
Failed connections (screenshots), `REJECT` flow-log lines, the containment timeline, the checklist document.

---

## 4.4 Member 5: Athena, detection use cases, runbook, CloudTrail evidence

### Console steps
**A. Create the Flow Logs table** (once, before the drill)
1. **Athena** > Query editor > workgroup **secnet**, database **secnet**.
2. **Saved queries** > `01-create-flow-logs-table` > Run. (In the console-first version, paste this SQL with your bucket name.)
```sql
CREATE EXTERNAL TABLE IF NOT EXISTS vpc_flow_logs (
  version int, account_id string, interface_id string,
  srcaddr string, dstaddr string, srcport int, dstport int,
  protocol bigint, packets bigint, bytes bigint,
  `start` bigint, `end` bigint, action string, log_status string)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ' '
LOCATION 's3://secnet-logs-<ACCOUNT_ID>/flowlogs/'
TBLPROPERTIES ('skip.header.line.count'='1');
```
3. `SELECT * FROM vpc_flow_logs LIMIT 10;`. Empty? Check the S3 path and that the flow logs use the **default format**.

**B. Detection queries** (saved queries 10 to 14). Run them **15 to 20 minutes after T1**: Flow Logs aggregate for 10 minutes and then deliver.

| Saved query | Detects |
|---|---|
| `10-top-rejected-sources` | who is hitting closed doors |
| `11-port-22-attempts` | any SSH. It should not exist in this design |
| `12-port-scan-pattern` | one source → more than 10 distinct rejected ports on one target |
| `13-unusual-outbound` | hub host → internet on ports other than 80/443/53/123 |
| `14-host-timeline` | every flow of one IP, in time order (edit `10.0.11.X`) |

Scanning costs $5 per TB. Our logs are a few MB, so each query costs a fraction of a cent.

**B2. CloudWatch near-real-time detection** (do the console version in Week 3 or early Week 4, Terraform keeps it on)

Athena (above) is the cheap long-term search over S3. **CloudWatch** catches things within minutes: the hub's flows (and Spoke A's when `enable_hybrid` is on) also go to CloudWatch Logs with **1-minute** aggregation. Metric filters turn matching log lines into numbers, and alarms email the team.

Console steps:
1. **CloudWatch** > **Log groups** > Create `/secnet/flowlogs/hub`, retention 14 days.
2. **IAM** > **Roles** > Create > *Custom trust policy* with principal `vpc-flow-logs.amazonaws.com`. Inline policy: `logs:CreateLogStream`, `logs:PutLogEvents`, `logs:DescribeLogStreams` on that log group only. Name it `secnet-flowlogs-to-cloudwatch`.
3. **VPC** > hub VPC > **Flow logs** > Create: filter **All**, interval **1 minute**, destination **CloudWatch Logs**, the log group, the role. (The S3 flow log from 2.5 stays: one VPC can have both.)
4. Log group > **Metric filters** > Create:
   - **Rejected flows from internal hosts**: pattern `[version, account_id, interface_id, srcaddr = "10.*", dstaddr, srcport, dstport, protocol, packets, bytes, start, end, action = "REJECT", log_status]`, namespace `secnet/Network`, metric `RejectedFlows`, value `1`, default `0`.
   - **Internal SSH attempts**: the same, but `dstport = 22` and `action` without a condition. Metric `SSHAttempts`.
   - Why `srcaddr = "10.*"`: the internet scans our ALB and NAT public IPs all day, and counting that noise would make the alarm useless. We alarm on *our own* hosts behaving badly (lateral movement).
5. **SNS** (eu-west-1) > topic `secnet-network-alerts` > email subscription > **confirm the email**.
6. **Alarms** > Create: `RejectedFlows` Sum over 5 min **> 25** → SNS. `SSHAttempts` Sum over 5 min **> 0** → SNS.
7. **Logs Insights** > query the log group and **Save** it as `secnet/top-rejected-sources`:
```
fields @timestamp, @message
| parse @message "* * * * * * * * * * * * * *" as version, account, eni, src, dst, srcport, dstport, proto, packets, bytes, start, end, action, status
| filter action = "REJECT"
| stats count(*) as rejects by src, dst, dstport
| sort rejects desc | limit 20
```
8. **Dashboards** > Create `secnet-network`: a line graph of both metrics + an alarm status widget.

Terraform (`modules/monitoring/cloudwatch.tf`, driven by `cloudwatch_flowlog_vpc_ids` in `envs/dev/main.tf`):
| Block | Console step |
|---|---|
| `aws_cloudwatch_log_group.flowlogs` | 1 |
| `aws_iam_role.flowlogs` + `aws_iam_role_policy.flowlogs` (write to these groups only, trust scoped by `aws:SourceAccount`) | 2 |
| `aws_flow_log.cloudwatch` (`max_aggregation_interval = 60`) | 3 |
| `aws_cloudwatch_log_metric_filter.rejects` / `.ssh` | 4 |
| `aws_sns_topic.network_alerts` + email subscription | 5 |
| `aws_cloudwatch_metric_alarm.rejects` / `.ssh` (threshold = `reject_alarm_threshold`, default 25) | 6 |
| `aws_cloudwatch_query_definition.top_rejects` / `.port_scan` | 7 |
| `aws_cloudwatch_dashboard.network` | 8 |

During the drill (4.1), expect: the **SSH alarm** within about 2 to 6 minutes of T0 (the victim's port 22 attempts appear in the hub log); the **rejected-flows alarm** from Spoke A's log (the scan is REJECTed by Spoke A's SG); then **OK** emails after containment. Write each alarm time into the incident timeline: "time to detect" is a key metric in the final report.

Cost: CloudWatch Logs ingestion ≈ $0.57 per GB in eu-west-1. Our lab produces a few MB a day, so pennies.

**C. Detection use cases** (`docs/week4/detection-use-cases.md`):

| Use case | Signal | Query / source | Threshold | First response | MITRE ATT&CK |
|---|---|---|---|---|---|
| Internal port scan | many rejected ports from one host | 12 | > 10 ports | isolate the source host | T1046 Network Service Discovery |
| SSH attempts | any port 22 flow | 11 | any | identify the source, check the SGs | T1021.004 Remote Services: SSH |
| Odd outbound | private host → unusual port | 13 | new destination | check the process, isolate | T1071 Application Layer Protocol |
| Reject storm | high reject count from one IP | 10 | > 100 / 10 min | block in the NACL or WAF | - |
| Web attack burst | WAF BlockedRequests | alarm (3.5) | > 5 / 5 min | review the sampled requests | T1190 Exploit Public-Facing Application |
| Lateral SSH (real time) | internal port 22 flow | CloudWatch `SSHAttempts` alarm (B2) | > 0 / 5 min | isolate the source host | T1021.004 |
| Internal scan (real time) | rejected flows from 10.x | CloudWatch `RejectedFlows` alarm (B2) | > 25 / 5 min | identify and isolate the source | T1046 |

**D. CloudTrail evidence:** **CloudTrail** > **Event history**, filtered by *Resource name* = victim instance ID, then by *Event name* `ModifyInstanceAttribute` (SG swap), `PutRolePolicy` (Revoke active sessions adds an inline deny policy), `CreateSnapshot`. Download as CSV, then run `sha256sum` on it.
**Log file validation proof:**
```bash
aws cloudtrail validate-logs --trail-arn <trail_arn> --start-time <T0 in ISO8601>
```

**E. IR runbook** (`docs/runbooks/ir-runbook.md`). For each phase write who, what, how and the evidence:
1. **Detect:** alarm or query hit; time; who noticed.
2. **Triage:** real or false positive; which host; severity (low/medium/high/critical).
3. **Preserve:** snapshot, Flow Log export, CloudTrail export, pcap. Hash every file.
4. **Contain:** quarantine SG, revoke sessions, tag. Never terminate.
5. **Eradicate and recover:** rebuild from Terraform (`terraform apply -replace='aws_instance.victim[0]'`); never "clean" the old host; rotate secrets.
6. **Lessons learned:** what worked, what to improve, an owner and a date for each fix.

**Chain of custody** table for every artefact: *item, ID or file, SHA-256, collected by, collected at (UTC), stored at (S3 path, versioned), accessed by*.

### Terraform (`modules/monitoring/athena.tf`)
`aws_athena_database.this` (encrypted) and `aws_athena_named_query.this` with `for_each` over `local.queries`: the table DDL + five detections, already pointing at your bucket.

### Check it worked
Query 12 shows the victim's IP scanning `10.1.1.X`, query 11 shows the port 22 attempts, query 14's timeline lines up with T0/T1 and the containment time from CloudTrail. The runbook and the chain-of-custody table are complete.

---

## 4.5 Member 6: final report, presentation, cleanup

### Steps
1. **Final report** `docs/final-report.md`, built from every week's README:
   - architecture and design decisions;
   - the four weeks' deliverables and evidence links;
   - the incident report (timeline, root cause, impact, lessons);
   - a cost summary (Cost Explorer screenshot);
   - "who did what" matching `docs/team-roles.md`.
2. **Presentation:** `02-Presentation/*.pptx`. Each member presents their own workstream; that is what is graded. Rehearse once with a timer. Keep a screenshot ready for every live demo.
3. **The day before the presentation:** switch on what you will demo (`enable_hybrid`, `enable_vpn`, `enable_edge`) and re-run the strongSwan step.
4. **Cleanup day**, after grading:
```bash
cd terraform/envs/dev
terraform destroy          # read the list, type yes
```
- If a bucket is not empty, our buckets have `force_destroy = true`. Empty any console-made bucket by hand (S3 > **Empty**).
- If a resource is in use, destroy the dependent resource first and run again.
- Find leftovers: **Resource Groups & Tag Editor** > **Tag Editor**, all regions, tag `Project = secure-network`. Also check **EC2** > Snapshots (manual evidence snapshots are not in Terraform), Elastic IPs, CloudWatch log groups in us-east-1, CloudFront, WAF.
- Last: empty and delete the state bucket, delete all IAM access keys, keep the GitHub repo as your portfolio.

### Check it worked
The next day Cost Explorer shows ≈ $0, Tag Editor finds nothing, and the report and slides are in the repo.

---

## Final checklist (every member)
- [ ] My booklet deliverables are done and linked in my week README
- [ ] Screenshots are in `docs/evidence/`
- [ ] My Terraform is merged, and `fmt` + `validate` pass in CI
- [ ] I can explain every setting I used, in my own words
- [ ] My resources are destroyed and the account is clean
