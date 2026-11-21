# Week 4: Network monitoring, detection & IR

Guide: [`docs/guides/`](../guides/) · Evidence: [`docs/evidence/week4/`](../evidence/week4/)

## Deliverables

| Deliverable | Member(s) | Status | Link |
|---|---|---|---|
| Flow log queries | 5 Ahmed | Not started | |
| Detection use cases (Athena + CloudWatch alarms) | 5 Ahmed | Not started | |
| Compromised-instance IR runbook | 5 Ahmed, 4 Asmaa | Not started | |
| Evidence collection notes | 2 Ahlam, 5 Ahmed | Not started | |
| Final secure network report | 6 Alber | Not started | |

## Design review (2026-11-21): extra security layers for the Week 4 build

Defence-in-depth review of the whole design. Rule: build only what is cheap, low-risk and demoable
(each gets a test in `make demo`); everything else is documented as production design.

| # | Layer | Change | Status |
|---|---|---|---|
| D9 | Network / data | Isolated DB subnets 10.0.21.0/24 + 10.0.22.0/24: local route only, own NACL (3306 from app subnets + return ports) | Built ✅ |
| D10 | Detection | GuardDuty (VPC flow, DNS, CloudTrail analysis) | Built ✅ |
| D11 | Detection / compliance | AWS Config rules: default SG closed, no SSH from 0.0.0.0/0 (continuous T7) | Built ✅ |
| D12 | Egress / DNS | Route 53 Resolver DNS Firewall on hub + spokes: AWS managed malware/botnet lists + own blocklist | Built ✅ |
| D13 | Detection / response | Security Hub (best-practice checks) + GuardDuty finding → EventBridge → SNS email | Built ✅ |
| D14 | Host / audit | Session Manager session logging (commands) to S3 / CloudWatch | Built ✅ |
| D15 | Data in transit | S3 bucket policies deny non-TLS; RDS `require_secure_transport`; IAM Access Analyzer | Built ✅ |

Documented only (production design, not built): NAT per AZ, web ASG, RDS Multi-AZ, second VPN tunnel,
hybrid DNS (Resolver endpoints), Network Firewall inspection VPC, log-archive account + Object Lock,
HTTPS origin / VPC origins, IAM Identity Center, KMS CMK for logs, WAF Bot Control, Shield Advanced,
VPC Block Public Access.

## Incident scenario IR-001: compromised web-tier server

| Phase | What happens | Tool / evidence | Test |
|---|---|---|---|
| Build | `enable_ir = true`: victim EC2 in the hub private subnet (web-tier SG + role), quarantine SG, baseline snapshot | plan / change log | – |
| Attack | `make ir-simulate`: port scan of Spoke A → 10 SSH attempts → C2 DNS lookup (GuardDuty test domain) → blocked exfil domain | `docs/incidents/IR-001-timeline.md` | T35 |
| Detect | CloudWatch alarms (spoke_a rejected flows, SSH) + GuardDuty high finding → emails | alarm + finding emails | T36 |
| Investigate | Athena 11 (port 22), 12 (port scan), 14 (victim timeline); GuardDuty finding details | query results | T37 |
| Preserve | EBS snapshot tagged `Case=IR-001`, `Phase=pre-containment` **before** containment | snapshot ID | T38 |
| Contain | `isolate_victim = true`: quarantine SG (no rules) **+ NACL deny in/out** for the victim /32 (a SG swap does not cut tracked connections; a NACL does) | plan / apply | T39 (automated) |
| Audit | CloudTrail: `ModifyNetworkInterfaceAttribute`, `ReplaceNetworkAclEntry` by secnet-lab | CloudTrail events | T40 |
| Recover | evidence kept, victim rebuilt or removed from code (`enable_ir = false`) | plan / apply | – |
| Lessons | e.g. web and victim share one IAM role → revoking sessions would also hit the web server | runbook lessons table | – |

### IR-001 rehearsal result (2026-11-21): all phases done

| Test | Result |
|---|---|
| T35 attack leaves traces | scan 0/80 open, SSH 0/10, C2 lookup, exfil domain BLOCKED ✅ |
| T36 automatic detection | 3 alarms in ~1 min, GuardDuty sev 8 on the victim in ~3 min, all emailed ✅ |
| T37 investigation | Athena 12: 10.0.11.222 → 10.1.1.46, 80 ports; query 15 timeline from 20:12:42 ✅ |
| T38 evidence before containment | snap-055cac4e403b6e6d9 at 20:42:02, completed, kept ✅ |
| T39 containment, site up | SG secnet-isolation + 2 NACL denies, ping FAIL, website 200 ✅ |
| T40 audited | CreateTags, ModifyNetworkInterfaceAttribute, 2 × CreateNetworkAclEntry by secnet-lab ✅ |
| Recover | rebuilt from code, infected instance terminated ✅ |

Full timeline: `../incidents/IR-001-timeline.md` · lessons: `../runbooks/ir-runbook.md` · evidence: `../evidence/week4/w4-T3*`, `w4-T40*`.

### Rehearsal measurements (2026-11-21, T0 = 20:12:17 UTC)

| Detection | Fired at | After the action |
|---|---|---|
| Spoke A rejected-flows alarm (80 rejects) | 20:13:53 | ~1 min after the scan |
| Hub + Spoke A SSH alarms | 20:13:56 / 20:14:01 | ~40 s after the SSH attempts |
| GuardDuty Backdoor:EC2/C&CActivity.B!DNS (sev 8) on the victim, email | 20:17 | ~3 min after the C2 lookup |
| Alarms back to OK | 20:18:53 | by themselves once traffic stopped |

Demo timing: alarms and GuardDuty were both in the inbox ≈5 min after T0. The alarms return to OK after
≈5 min, so in the demo show the emails / alarm history, not only the current state.

## What we built

## Tests (command · expected · actual)

Applied 2026-11-21 ~19:10 UTC (43 added, 1 changed, 2 destroyed). `make demo ARGS="--week 4 --auto"`
at 19:13 UTC: **9 passed, 0 failed** (log `../evidence/week4/w4-layers-run-2026-11-21.log`).

| # | Command | Expected | Actual |
|---|---|---|---|
| T42 | `dig <db>` + data route table: count 0.0.0.0/0 | db 10.0.21/22.x · 0 internet routes | 10.0.21.133 · 0 ✅ |
| T43 | office router → db :3306 (SSM) | CLOSED | CLOSED ✅ |
| T5 | web → db :3306 (regression after the move) | OPEN | OPEN ✅ |
| T44 | `guardduty get-detector` | ENABLED | ENABLED ✅ |
| T45 | DNS lookup from web: `c2.evil-demo.example` / `aws.amazon.com` | BLOCKED / allowed | BLOCKED / allowed ✅ |
| T46 | Config compliance | both rules COMPLIANT | first run: default-sg-closed NON_COMPLIANT (default VPC default SG) → fixed in code → COMPLIANT · COMPLIANT ✅ |
| T47 | Security Hub standards + Access Analyzer | READY 1 · ACTIVE | READY 1 · ACTIVE ✅ |
| T48 | Session Manager preferences | logged to /secnet/ssm-sessions | ✅ |
| T49 | bucket policies + RDS parameter | 2 of 2 · require_secure_transport=1 | ✅ |
| SNS | `secnet-security-findings` email subscription | confirmed | confirmed ✅ |
| T50 | `guardduty create-sample-findings` – Low (`Recon:EC2/PortProbeUnprotectedPort`) then High (`Backdoor:EC2/C&CActivity.B!DNS`) | Low: dashboard only, no email (rule = severity ≥ 4) · High: email | Low: dashboard only ✅ · High: email at 19:40 UTC, "GuardDuty finding (severity 8): …" ✅ (`w4-T50-guardduty-{low-sample,high-email}.png`) |
| T51 | Session Manager shell on web: `whoami`, `hostname`, `echo "T51 audit test $(date)"`; then `aws logs filter-log-events --log-group-name /secnet/ssm-sessions` | who, when, which instance, every command | userIdentity `user/secnet-lab`, session ID, target i-08a08b9eb949195eb, runAs ssm-user, all 3 commands + output, 19:43:54 UTC ✅ (`w4-T51-session-{commands,log-cloudwatch}.png`) |

Full regression after the Week 4 build (2026-11-21 19:16 UTC, Weeks 1–4): **35 passed, 0 failed, 0 skipped**
(`../evidence/regression-2026-11-21-weeks1-4.log`). T2/T34 now resolve the DB to 10.0.21.x (isolated tier).

## Problems and how we fixed them

- **Config finding (detect → fix → verify):** `secnet-default-sg-closed` flagged `sg-0383255b9acb5d03e`, the default SG
  of the account's default VPC (outside the project; built-in allow-self / allow-all-egress rules). Fixed in code with
  `aws_default_security_group` and no rules → rules 0/0 → Config COMPLIANT two minutes later. Logs
  `../evidence/week4/w4-T46-config-{before,after}-fix.log`. T46 now requires both rules COMPLIANT.
  Production recommendation: delete the default VPC (account-owner decision).
- **GuardDuty drift:** AWS adds an `RDS_DATA_RISK` sub-setting to the RDS_LOGIN_EVENTS feature, so every plan wanted to
  replace it. Provider 5.x cannot declare that name (validation error), so `ignore_changes = [additional_configuration]`
  with a comment; revisit on provider upgrade.

## Cost and cleanup

Hours with each switch on, Cost Explorer screenshot, `make sleep` runs.
