#!/usr/bin/env bash
# Demo test runner: every automated test from docs/demo-test-plan.md, read-only.
#
#   make demo                     interactive: shows what each test proves, waits for Enter, runs it
#   make demo ARGS="--auto"       no pauses (rehearsal / evidence run)
#   scripts/demo-tests.sh --only T1,T17,T29      just these tests
#   scripts/demo-tests.sh --week 2               one week only
#   scripts/demo-tests.sh --with-plan            also T11 (terraform plan, ~1 min)
#   scripts/demo-tests.sh --slow                 also T31 (WAF rate limit, ~1 min, trips the WAF alarm)
#
# All IDs/IPs come from `terraform output`. Tests inside AWS run through SSM Run Command (no SSH,
# every command is in CloudTrail). Drills that CHANGE something (T6, T21b, T32, T39) stay manual.
# Works with the macOS default bash 3.2. Needs: terraform, aws (profile secnet), curl, dig, nc.

set -u
cd "$(dirname "$0")/.." || exit 1
TFDIR=terraform/envs/dev
P="--profile ${AWS_PROFILE:-secnet} --region eu-west-1"
AUTO=0; ONLY=""; WEEK=""; WITH_PLAN=0; SLOW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --auto|-y) AUTO=1 ;;
    --only) ONLY=",$2,"; shift ;;
    --week) WEEK="$2"; shift ;;
    --with-plan) WITH_PLAN=1 ;;
    --slow) SLOW=1 ;;
    -h|--help) sed -n 2,14p "$0"; exit 0 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
  shift
done

if [ -t 1 ]; then B=$'\e[1m'; D=$'\e[2m'; G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; C=$'\e[36m'; N=$'\e[0m'; else B=''; D=''; G=''; R=''; Y=''; C=''; N=''; fi
LOG="demo-run-$(date +%Y%m%d-%H%M).log"
PASS=0; FAIL=0; SKIP=0; FAILED=""

out() { terraform -chdir="$TFDIR" output -raw "$1" 2>/dev/null; }
log() { printf '%s\n' "$*" | sed $'s/\e\\[[0-9;]*m//g' >> "$LOG"; }
say() { printf '%s\n' "$*"; log "$*"; }

# run a shell snippet on an instance through SSM Run Command; prints its stdout
ssm_run() {
  local id="$1" b64 cid st i
  b64=$(printf '%s' "$2" | base64 | tr -d '\n')
  cid=$(aws ssm send-command $P --instance-ids "$id" --document-name AWS-RunShellScript \
        --comment "demo-tests" --timeout-seconds 60 \
        --parameters "{\"commands\":[\"echo $b64 | base64 -d | bash\"]}" \
        --query Command.CommandId --output text 2>/dev/null) || { echo "SSM-ERROR"; return; }
  for i in $(seq 1 45); do
    sleep 2
    st=$(aws ssm get-command-invocation $P --command-id "$cid" --instance-id "$id" --query Status --output text 2>/dev/null)
    case "$st" in Success|Failed|TimedOut|Cancelled) break ;; esac
  done
  aws ssm get-command-invocation $P --command-id "$cid" --instance-id "$id" \
    --query StandardOutputContent --output text 2>/dev/null | tr '\n' ' ' | sed 's/ *$//'
}

# what each test runs, in plain words: "where it runs|the command" (values filled in at run time)
LAPTOP="my laptop (= any user on the internet)"
VIA_SSM="inside AWS (no SSH) – Session Manager runs it on"
explain() {
  case "$1" in
    T1)  echo "$LAPTOP|curl $ENTRY   → print only the HTTP status code" ;;
    T2)  echo "$LAPTOP|dig $DB  (which IP?)  +  nc -z $DB 3306  (is the DB port reachable?)" ;;
    T3)  echo "AWS API|aws ec2 describe-instances --instance-ids $WEB --query PublicIpAddress" ;;
    T4)  echo "$VIA_SSM the web server|hostname; whoami   (no SSH key, no port 22)" ;;
    T5)  echo "$VIA_SSM the web server|open a TCP connection to $DB port 3306" ;;
    T7)  echo "AWS API|aws ec2 describe-security-groups → count rules that open port 22 or ALL traffic to 0.0.0.0/0" ;;
    T8)  echo "AWS API|aws ec2 describe-security-groups --filters vpc=$HUBVPC group-name=default → count rules" ;;
    T9)  echo "AWS API|aws ec2 describe-network-acls --filters Name=secnet-private-nacl → subnets + deny rules" ;;
    T10) echo "AWS API|aws cloudtrail get-trail-status --name secnet-trail" ;;
    T11) echo "my laptop|terraform plan -detailed-exitcode   (exit 0 = code and AWS are identical)" ;;
    T13) echo "AWS API|aws budgets describe-budget --budget-name secnet-monthly" ;;
    T14) echo "$VIA_SSM the hub web server|ping $SAIP   (Spoke A, via VPC peering)" ;;
    T15) echo "$VIA_SSM the hub web server|ping $SBIP; curl http://$SBIP   (Spoke B, via Transit Gateway)" ;;
    T16) echo "$VIA_SSM Spoke A|ping $SBIP   (Spoke B – would need to pass THROUGH the hub)" ;;
    T17) echo "AWS API + $VIA_SSM the office router|aws ec2 describe-vpn-connections (tunnel status)  +  ping $WEBIP from 192.168.x.x" ;;
    T18) echo "$VIA_SSM the office router|ping $SBIP   (office → Spoke B)" ;;
    T19) echo "$VIA_SSM Spoke A|curl https://aws.amazon.com   (does it have internet?)" ;;
    T20) echo "$VIA_SSM Spoke B|getent hosts ssm.eu-west-1.amazonaws.com   (public name → private IP?)" ;;
    T21) echo "$VIA_SSM the hub web server|curl http://<privatelink-endpoint>; try TCP 80 and TCP 22" ;;
    T26) echo "AWS API|for every project VPC: aws ec2 describe-flow-logs → status ACTIVE?" ;;
    T27) echo "$LAPTOP|curl https://$BUCKET.s3.eu-west-1.amazonaws.com/index.html   (skip CloudFront, go to S3 directly)" ;;
    T28) echo "$LAPTOP|curl $CF" ;;
    T29) echo "$LAPTOP|curl \"$CF?id=1' OR '1'='1\"   (classic SQL injection)" ;;
    T30) echo "$LAPTOP|curl \"$CF?q=<script>alert(1)</script>\"   (cross-site scripting)" ;;
    T31) echo "$LAPTOP|300 × curl $CF as fast as possible → count the status codes" ;;
    T1b) echo "$LAPTOP|curl -m 6 $ALB   (skip CloudFront, go to the load balancer directly)" ;;
    T29b) echo "$LAPTOP|curl \"${APP}?id=1' OR '1'='1\"   (SQL injection against the web app)" ;;
    T34) echo "$VIA_SSM the web server + AWS API|getent hosts db.secnet.internal  +  aws route53 get-health-check-status" ;;
    T42) echo "AWS API|dig $DB (which subnet?)  +  aws ec2 describe-route-tables $DATART → count 0.0.0.0/0 routes" ;;
    T43) echo "$VIA_SSM the office router|open a TCP connection to $DB port 3306   (office → database)" ;;
    T44) echo "AWS API|aws guardduty get-detector --detector-id $GD → Status" ;;
    T45) echo "$VIA_SSM the web server|DNS lookup of c2.evil-demo.example (on our blocklist) and of aws.amazon.com (normal)" ;;
    T46) echo "AWS API|aws configservice describe-compliance-by-config-rule (default SG closed · no SSH from internet)" ;;
    T47) echo "AWS API|aws securityhub get-enabled-standards  +  aws accessanalyzer list-analyzers" ;;
    T48) echo "AWS API|aws ssm get-document --name SSM-SessionManagerRunShell → where are sessions logged?" ;;
    T49) echo "AWS API|aws s3api get-bucket-policy (site + logs) → deny non-TLS?  +  RDS parameter require_secure_transport" ;;
    *)   echo "|" ;;
  esac
}

PING='ping -c2 -W2 %s >/dev/null 2>&1 && echo "ping OK" || echo "ping FAIL"'
ping_cmd() { printf "$PING" "$1"; }

# t ID WEEK "title" "proves (say this)" "expected (shown)" "regex the result must match" func [needs...]
t() {
  local id="$1" wk="$2" title="$3" why="$4" exp="$5" re="$6" fn="$7"; shift 7
  if [ -n "$ONLY" ] && [ "${ONLY#*,"$id",}" = "$ONLY" ]; then return; fi
  if [ -n "$WEEK" ] && [ "$WEEK" != "$wk" ]; then return; fi
  say ""
  say "${C}━━━ ${B}$id${N}${C} · $title ━━━${N}"
  say "  ${B}Proves:${N}   $why"
  local ex where cmd; ex=$(explain "$id"); where=${ex%%|*}; cmd=${ex#*|}
  [ -n "$where" ] && say "  ${B}Runs on:${N}  $where"
  [ -n "$cmd" ]   && say "  ${B}Command:${N}  ${Y}$cmd${N}"
  say "  ${B}Expected:${N} $exp"
  local need
  for need in "$@"; do
    if [ -z "$need" ]; then say "  ${Y}SKIP${N}     not deployed (switch off) – nothing to test"; SKIP=$((SKIP+1)); return; fi
  done
  if [ "$AUTO" = 0 ]; then printf '  %s' "${D}[Enter] to run …${N}"; read -r _ </dev/tty; fi
  local res; res=$($fn 2>&1)
  if printf '%s' "$res" | grep -Eq "$re"; then
    say "  ${B}Result:${N}   $res   ${G}${B}✔ PASS${N}"; PASS=$((PASS+1))
  else
    say "  ${B}Result:${N}   $res   ${R}${B}✘ FAIL${N}"; FAIL=$((FAIL+1)); FAILED="$FAILED $id"
  fi
}

say "${B}Secure AWS Network – demo tests${N}   $(date '+%Y-%m-%d %H:%M')"
say "${D}reading terraform outputs …${N}"
ACCOUNT=$(aws sts get-caller-identity $P --query Account --output text 2>/dev/null) || { echo "AWS login failed (profile secnet)"; exit 1; }
ALB=$(out alb_url); DB=$(out db_endpoint); WEB=$(out web_instance_id); WEBIP=$(out web_private_ip)
HUBVPC=$(out hub_vpc_id); SA=$(out spoke_a_instance_id); SB=$(out spoke_b_instance_id)
SAIP=$(out spoke_a_ip); SBIP=$(out spoke_b_ip); SW=$(out strongswan_instance_id); SWIP=$(out strongswan_private_ip)
VPN=$(out vpn_connection_id); PL=$(out privatelink_dns); CF=$(out cloudfront_url); BUCKET=$(out site_bucket)
HC=$(out alb_health_check_id); APP=$(out app_url)
DATART=$(out data_route_table_id); GD=$(out guardduty_detector_id); SSMLOG=$(out ssm_session_log_group)
# Week 3 puts CloudFront in front of the ALB: the app is then reached only via APP
ENTRY=${APP:-$ALB}
onoff() { [ -n "$1" ] && echo on || echo off; }
say ""
say "${B}How to read the results${N}"
say "  ${B}200${N} = page served OK   ${B}403${N} = refused by a security rule (WAF / bucket policy / ALB)"
say "  ${B}000${N} = no answer at all (a firewall dropped the connection)   ${B}ping FAIL${N} = no network path"
say "  ${R}❌${N} next to Expected means we WANT it to be blocked – a block is a PASS."
say "  ${D}Commands are shortened for reading; the exact code is in scripts/demo-tests.sh.${N}"
say "${D}stack: web ${WEB:-–} · spokes $(onoff "$SA") · VPN $(onoff "$VPN") · edge $(onoff "$CF")${N}"

# ---------------- Week 1: the hub ----------------
T1()  { curl -s -o /dev/null -m 10 -w "%{http_code}" "$ENTRY"; }
T2()  { local ip; ip=$(dig +short "$DB" | tail -1); nc -z -G 5 "$DB" 3306 >/dev/null 2>&1 && echo "$ip port 3306 OPEN" || echo "$ip port 3306 blocked"; }
T3()  { aws ec2 describe-instances $P --instance-ids "$WEB" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text; }
T4()  { ssm_run "$WEB" 'echo "shell on $(hostname) as $(whoami)"'; }
T5()  { ssm_run "$WEB" "timeout 3 bash -c '</dev/tcp/$DB/3306' 2>/dev/null && echo 'port 3306 OPEN' || echo 'port 3306 CLOSED'"; }
# Both conditions must hold in the SAME rule (EC2 API filters would match across rules of one SG)
T7()  { local n22 nall
        n22=$(aws ec2 describe-security-groups $P --output text \
          --query 'length(SecurityGroups[?IpPermissions[?FromPort<=`22` && ToPort>=`22` && IpRanges[?CidrIp==`0.0.0.0/0`]]])')
        nall=$(aws ec2 describe-security-groups $P --output text \
          --query 'length(SecurityGroups[?IpPermissions[?IpProtocol==`-1` && IpRanges[?CidrIp==`0.0.0.0/0`]]])')
        echo "SGs with port 22: $n22 · all-traffic from internet: $nall"; }
T8()  { aws ec2 describe-security-groups $P --filters Name=vpc-id,Values="$HUBVPC" Name=group-name,Values=default \
          --query 'SecurityGroups[0].[length(IpPermissions),length(IpPermissionsEgress)]' --output text | awk '{print "inbound " $1 " · outbound " $2}'; }
T9()  { aws ec2 describe-network-acls $P --filters Name=tag:Name,Values=secnet-private-nacl \
          --query 'NetworkAcls[0].[length(Associations), length(Entries[?RuleAction==`deny`])]' --output text | awk '{print $1 " subnets · " $2 " deny rules"}'; }
T10() { aws cloudtrail get-trail-status $P --name secnet-trail --query IsLogging --output text | sed 's/^/IsLogging /'; }
T11() { terraform -chdir="$TFDIR" plan -lock=false -detailed-exitcode -input=false >/dev/null 2>&1; case $? in 0) echo "No changes";; 2) echo "CHANGES PENDING";; *) echo "plan error";; esac; }
T13() { aws budgets describe-budget $P --account-id "$ACCOUNT" --budget-name secnet-monthly --query 'Budget.[BudgetName,BudgetLimit.Amount]' --output text; }

t T1 1 "Website reachable" "the internet reaches the app (Week 1: via the ALB · Week 3: via CloudFront + WAF → ALB)" "HTTP 200" '^200$' T1 "$ENTRY"
t T2 1 "Database has no public path" "the DB name resolves to a private IP and port 3306 is closed from the internet" "10.0.x.x · port 3306 blocked" '^10\..* blocked$' T2 "$DB"
t T3 1 "Web server has no public IP" "it can only be reached through the ALB" "None" '^None$' T3 "$WEB"
t T4 1 "Admin shell without SSH" "Session Manager / Run Command works with no key and no open port" "shell on ip-10-0-… as root" '^shell on ip-10-0' T4 "$WEB"
t T5 1 "App tier can reach the database (allowed path)" "the SG chain allows web → RDS :3306" "port 3306 OPEN" 'OPEN' T5 "$WEB" "$DB"
t T7 1 "Nothing allows SSH or all traffic from the internet" "no security group in the account opens port 22 or everything to 0.0.0.0/0" "port 22: 0 · all-traffic: 0" 'port 22: 0 .*internet: 0$' T7 "$ACCOUNT"
t T8 1 "Default security group is empty" "anything launched without an SG gets no network access" "inbound 0 · outbound 0" '^inbound 0 .* outbound 0$' T8 "$HUBVPC"
t T9 1 "Private subnets have a second filter (NACL)" "a stateless subnet-level layer behind the security groups" "2 subnets" '^2 subnets' T9 "$HUBVPC"
t T10 1 "Every API call is recorded" "CloudTrail is logging" "IsLogging True" 'True' T10 "$ACCOUNT"
t T13 1 "Spending is guarded" "the monthly budget exists and alerts by email" "secnet-monthly 50…" '^secnet-monthly' T13 "$ACCOUNT"
if [ "$WITH_PLAN" = 1 ]; then
t T11 1 "Live environment matches the code" "terraform plan finds no hidden manual changes (≈1 min)" "No changes" '^No changes$' T11 "$ACCOUNT"
fi

# ---------------- Week 2: hybrid connectivity ----------------
T14() { ssm_run "$WEB" "$(ping_cmd "$SAIP")"; }
T15() { ssm_run "$WEB" "$(ping_cmd "$SBIP"); curl -s -m 5 http://$SBIP || echo 'curl FAIL'"; }
T16() { ssm_run "$SA" "$(ping_cmd "$SBIP")"; }
T17() { local tun; tun=$(aws ec2 describe-vpn-connections $P --vpn-connection-ids "$VPN" --query 'length(VpnConnections[0].VgwTelemetry[?Status==`UP`])' --output text)
        echo "tunnels UP: $tun · $(ssm_run "$SW" "$(ping_cmd "$WEBIP")")"; }
T18() { ssm_run "$SW" "$(ping_cmd "$SBIP")"; }
T19() { ssm_run "$SA" "curl -s -m 5 -o /dev/null -w '%{http_code}' https://aws.amazon.com || true" | sed 's/^/internet: /'; }
T20() { ssm_run "$SB" "getent hosts ssm.eu-west-1.amazonaws.com | awk '{print \"ssm resolves to \" \$1}'"; }
T21() { ssm_run "$WEB" "curl -s -m 5 http://$PL || echo 'curl FAIL'; for p in 80 22; do timeout 5 bash -c \"</dev/tcp/$PL/\$p\" 2>/dev/null && echo \"\$p OPEN\" || echo \"\$p CLOSED\"; done"; }
T26() { local v n=0 ok=0
        for v in $(aws ec2 describe-vpcs $P --filters Name=tag:Project,Values=secure-network --query 'Vpcs[].VpcId' --output text); do
          n=$((n+1)); c=$(aws ec2 describe-flow-logs $P --filter Name=resource-id,Values="$v" --query 'length(FlowLogs[?FlowLogStatus==`ACTIVE`])' --output text 2>/dev/null)
          case "$c" in ''|*[!0-9]*) c=0 ;; esac; [ "$c" -gt 0 ] && ok=$((ok+1))
        done; echo "$ok of $n VPCs have active flow logs"; }

t T14 2 "Hub ↔ Spoke A over VPC peering" "routes on both sides let the hub reach Spoke A" "ping OK" '^ping OK$' T14 "$SA"
t T15 2 "Hub ↔ Spoke B over Transit Gateway" "the hub reaches Spoke B through the TGW (hub route table)" "ping OK Spoke B service" 'ping OK Spoke B service' T15 "$SB"
t T16 2 "Peering is NOT transitive" "Spoke A cannot use the hub to reach Spoke B" "ping FAIL ❌" '^ping FAIL$' T16 "$SA" "$SB"
t T17 2 "Office reaches the hub over the IPsec VPN" "encrypted Site-to-Site VPN, office router → hub web server" "tunnels UP: 1 · ping OK" 'UP: [12] .* ping OK$' T17 "$SW" "$VPN"
t T18 2 "Segmentation: office cannot reach Spoke B" "the office TGW route table has no route to 10.2.0.0/16 (Spoke B's SG would allow it)" "ping FAIL ❌" '^ping FAIL$' T18 "$SW" "$SB"
t T19 2 "Spokes have no internet" "no internet gateway, no NAT in the spokes" "internet: 000 ❌" 'internet: 000' T19 "$SA"
t T20 2 "Private hosts managed through VPC endpoints" "SSM works in Spoke B with no internet; the SSM name resolves to a private endpoint IP" "ssm resolves to 10.2.x.x" 'resolves to 10\.2\.' T20 "$SB"
t T21 2 "PrivateLink: one service, one port, no routing" "the hub reaches Spoke B's web service on :80 only" "Spoke B service · 80 OPEN · 22 CLOSED" 'Spoke B service 80 OPEN 22 CLOSED' T21 "$PL"
t T26 2 "All traffic is recorded" "every VPC in the project has active flow logs" "N of N VPCs" '^([0-9]+) of \1 VPCs' T26 "$ACCOUNT"

# ---------------- Week 3: edge security ----------------
T27() { curl -s -o /dev/null -m 10 -w "%{http_code}" "https://$BUCKET.s3.eu-west-1.amazonaws.com/index.html"; }
T28() { curl -s -o /dev/null -m 10 -w "%{http_code}" "$CF"; }
T29() { curl -s -o /dev/null -m 10 -w "%{http_code}" -G "$CF" --data-urlencode "id=1' OR '1'='1"; }
T30() { curl -s -o /dev/null -m 10 -w "%{http_code}" -G "$CF" --data-urlencode "q=<script>alert(1)</script>"; }
T31() { local i; for i in $(seq 1 300); do curl -s -o /dev/null -m 5 -w "%{http_code}\n" "$CF"; done | sort | uniq -c | awk '{printf "%s×%s ", $1, $2}'; }
# The ALB must refuse anyone who is not CloudFront: SG = CloudFront prefix list -> connection times out (000)
T1b() { curl -s -o /dev/null -m 6 -w "%{http_code}" "$ALB"; }
T29b(){ curl -s -o /dev/null -m 10 -w "%{http_code}" -G "$APP" --data-urlencode "id=1' OR '1'='1"; }
T34() { local hc; hc=$(aws route53 get-health-check-status $P --health-check-id "$HC" --query 'HealthCheckObservations[].StatusReport.Status' --output text | tr '\t' '\n' | grep -c '^Success')
        echo "db.secnet.internal -> $(ssm_run "$WEB" "getent hosts db.secnet.internal | awk '{print \$1}'") · health checkers OK: $hc"; }

t T27 3 "The S3 bucket behind the site is private" "only CloudFront (OAC) may read it; direct access is refused" "403 ❌" '^403$' T27 "$BUCKET"
t T28 3 "Site served over HTTPS through CloudFront" "the static site works through the edge" "200" '^200$' T28 "$CF"
t T29 3 "WAF blocks SQL injection" "AWS managed SQLi rules stop the attack at the edge" "403 ❌" '^403$' T29 "$CF"
t T1b 3 "Nobody can bypass CloudFront" "the ALB accepts only CloudFront's IP ranges + a secret header; direct access times out" "000 ❌" '^000$' T1b "$APP"
t T29b 3 "WAF also protects the web app" "the same SQL injection against the app (CloudFront → ALB) is blocked at the edge" "403 ❌" '^403$' T29b "$APP"
t T30 3 "WAF blocks cross-site scripting" "AWS managed common rules stop the XSS payload" "403 ❌" '^403$' T30 "$CF"
if [ "$SLOW" = 1 ]; then
t T31 3 "WAF rate limit stops floods" "300 requests from one IP: the rate rule starts returning 403 (≈1 min)" "mix of 200 and 403" '403' T31 "$CF"
fi
t T34 3 "Private DNS + end-to-end health check" "db.secnet.internal resolves to a private IP inside the VPC only; Route 53 checkers see CloudFront → ALB → web healthy" "10.0.x.x · health checkers OK: >0" '10\.0\..* health checkers OK: [1-9]' T34 "$HC"

# ---------------- Week 4: extra security layers (D9-D15) ----------------
DNSCHECK='python3 - <<"PY"
import socket, struct, random
def ask(name):
    q = struct.pack(">HHHHHH", random.randint(0, 65535), 0x0100, 1, 0, 0, 0)
    q += b"".join(bytes([len(p)]) + p.encode() for p in name.split(".")) + b"\0" + struct.pack(">HH", 1, 1)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3)
    s.sendto(q, ("169.254.169.253", 53)); r = s.recv(512)
    return "BLOCKED" if b"dns-firewall-blocked" in r else ("allowed" if (r[3] & 15) == 0 else "rcode %d" % (r[3] & 15))
print("c2.evil-demo.example: %s · aws.amazon.com: %s" % (ask("c2.evil-demo.example"), ask("aws.amazon.com")))
PY'
T42() { local ip n; ip=$(dig +short "$DB" | tail -1)
        n=$(aws ec2 describe-route-tables $P --route-table-ids "$DATART" --query 'length(RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`])' --output text)
        echo "db $ip · internet routes: $n"; }
T43() { ssm_run "$SW" "timeout 4 bash -c '</dev/tcp/$DB/3306' 2>/dev/null && echo 'port 3306 OPEN' || echo 'port 3306 CLOSED'"; }
T44() { aws guardduty get-detector $P --detector-id "$GD" --query Status --output text | sed 's/^/GuardDuty /'; }
T45() { ssm_run "$WEB" "$DNSCHECK"; }
T46() { local a b
        a=$(aws configservice describe-compliance-by-config-rule $P --config-rule-names secnet-default-sg-closed --query 'ComplianceByConfigRules[0].Compliance.ComplianceType' --output text)
        b=$(aws configservice describe-compliance-by-config-rule $P --config-rule-names secnet-restricted-ssh --query 'ComplianceByConfigRules[0].Compliance.ComplianceType' --output text)
        echo "default-sg-closed: $a · restricted-ssh: $b"; }
T47() { local st an
        st=$(aws securityhub get-enabled-standards $P --query 'length(StandardsSubscriptions[?StandardsStatus==`READY`])' --output text 2>/dev/null)
        an=$(aws accessanalyzer list-analyzers $P --type ACCOUNT --query 'analyzers[0].status' --output text 2>/dev/null)
        echo "Security Hub standards READY: ${st:-0} · Access Analyzer: $an"; }
T48() { aws ssm get-document $P --name SSM-SessionManagerRunShell --query Content --output text | grep -q "$SSMLOG" && echo "sessions logged to $SSMLOG" || echo "session logging NOT configured"; }
T49() { local n=0 b v
        for b in "$BUCKET" "$(out logs_bucket)"; do aws s3api get-bucket-policy $P --bucket "$b" --query Policy --output text 2>/dev/null | grep -q '"aws:SecureTransport":"false"' && n=$((n+1)); done
        v=$(aws rds describe-db-parameters $P --db-parameter-group-name secnet-mysql84-tls --query "Parameters[?ParameterName=='require_secure_transport'].ParameterValue" --output text 2>/dev/null)
        echo "buckets denying non-TLS: $n of 2 · RDS require_secure_transport=$v"; }

t T42 4 "Database in isolated data subnets" "RDS sits in its own subnets whose route table has no way to the internet (D9)" "db 10.0.21/22.x · internet routes: 0" '^db 10\.0\.2[12]\..* internet routes: 0$' T42 "$DATART"
t T43 4 "Office cannot reach the database" "VPN users reach the hub, never the data tier: no route back + data NACL (D9)" "port 3306 CLOSED ❌" 'CLOSED' T43 "$SW" "$DATART"
t T5 4 "…but the app tier still can (regression)" "web → RDS :3306 still works after moving the DB" "port 3306 OPEN" 'OPEN' T5 "$WEB" "$DB"
t T44 4 "Threat detection is on" "GuardDuty analyses CloudTrail, VPC Flow Logs and DNS queries (D10)" "GuardDuty ENABLED" 'ENABLED' T44 "$GD"
t T45 4 "DNS Firewall blocks bad domains" "a server cannot look up a domain on the blocklist, even though NAT allows outbound (D12)" "c2.evil-demo.example: BLOCKED ❌ · aws.amazon.com: allowed" 'evil-demo.example: BLOCKED .* allowed' T45 "$WEB"
t T46 4 "Misconfigurations are detected continuously" "AWS Config re-checks every security group on each change (T7, automated – D11)" "default-sg-closed: COMPLIANT · restricted-ssh: COMPLIANT" '^default-sg-closed: COMPLIANT .* restricted-ssh: COMPLIANT$' T46 "$GD"
t T47 4 "One security dashboard" "Security Hub runs the AWS best-practice checks; Access Analyzer flags external access (D13, D15)" "standards READY: 1 · Access Analyzer: ACTIVE" 'READY: 1 .* ACTIVE' T47 "$GD"
t T48 4 "Every admin session is recorded" "Session Manager streams each shell (who, when, every command) to CloudWatch (D14)" "sessions logged to /secnet/ssm-sessions" '^sessions logged to' T48 "$SSMLOG"
t T49 4 "Encryption in transit is mandatory" "S3 refuses plain HTTP; MySQL refuses clients without TLS (D15)" "2 of 2 · require_secure_transport=1" '2 of 2 .*=1$' T49 "$BUCKET"

# ---------------- summary ----------------
say ""
say "${B}Summary:${N} ${G}$PASS passed${N} · ${R}$FAIL failed${N} · ${Y}$SKIP skipped${N}${FAILED:+   failed:$FAILED}"
say "${D}Manual drills (they change something): T6 drift, T21b NACL deny, T32 geo-block, T33 WAF alarm email, T35–T41 incident, T50 GuardDuty sample finding → email, T51 session log review.${N}"
say "${D}Log: $LOG${N}"
[ "$FAIL" = 0 ]
