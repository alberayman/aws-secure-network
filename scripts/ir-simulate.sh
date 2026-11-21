#!/usr/bin/env bash
# IR-001 attack simulation: makes the "victim" behave like a compromised server, step by step,
# and explains each step for the audience. Read-only towards AWS config; it only generates traffic.
#
#   make ir-simulate            interactive (Enter before each step)
#   make ir-simulate ARGS=--auto
#
# Runs on the victim through SSM Run Command (no SSH; every command is in CloudTrail).
# Appends each step to docs/incidents/IR-001-timeline.md (UTC).
# Needs: enable_ir = true (victim), enable_hybrid = true (Spoke A target), terraform, aws (profile secnet).

set -u
cd "$(dirname "$0")/.." || exit 1
TFDIR=terraform/envs/dev
P="--profile ${AWS_PROFILE:-secnet} --region eu-west-1"
AUTO=0; [ "${1:-}" = "--auto" ] && AUTO=1
TL=docs/incidents/IR-001-timeline.md
if [ -t 1 ]; then B=$'\e[1m'; D=$'\e[2m'; C=$'\e[36m'; Y=$'\e[33m'; N=$'\e[0m'; else B=''; D=''; C=''; Y=''; N=''; fi

out() { terraform -chdir="$TFDIR" output -raw "$1" 2>/dev/null; }
now() { date -u '+%Y-%m-%d %H:%M:%S'; }

ssm_run() {
  local id="$1" b64 cid st i
  b64=$(printf '%s' "$2" | base64 | tr -d '\n')
  cid=$(aws ssm send-command $P --instance-ids "$id" --document-name AWS-RunShellScript \
        --comment "IR-001 simulation" --timeout-seconds 120 \
        --parameters "{\"commands\":[\"echo $b64 | base64 -d | bash\"]}" \
        --query Command.CommandId --output text 2>/dev/null) || { echo "SSM-ERROR"; return; }
  for i in $(seq 1 60); do
    sleep 2
    st=$(aws ssm get-command-invocation $P --command-id "$cid" --instance-id "$id" --query Status --output text 2>/dev/null)
    case "$st" in Success|Failed|TimedOut|Cancelled) break ;; esac
  done
  aws ssm get-command-invocation $P --command-id "$cid" --instance-id "$id" \
    --query StandardOutputContent --output text 2>/dev/null | sed 's/^/      /'
}

VICTIM=$(out victim_instance_id); VIP=$(out victim_private_ip); TARGET=$(out spoke_a_ip)
[ -n "$VICTIM" ] || { echo "No victim: set enable_ir = true and apply first."; exit 1; }
[ -n "$TARGET" ] || { echo "No Spoke A: enable_hybrid must be true."; exit 1; }

[ -f "$TL" ] || printf '# IR-001 timeline (UTC)\n\n| Time (UTC) | Event | Source | By |\n|---|---|---|---|\n' > "$TL"
mark() { printf '| %s | %s | %s | %s |\n' "$(now)" "$1" "$2" "${3:-simulation script}" >> "$TL"; }

step() {  # step "title" "what an attacker does" "what should detect it"
  echo; echo "${C}━━━ ${B}$1${N}"
  echo "  ${B}Attacker:${N}  $2"
  echo "  ${B}Detection:${N} $3"
  if [ "$AUTO" = 0 ]; then printf '  %s' "${D}[Enter] to run …${N}"; read -r _ </dev/tty; fi
}

echo "${B}IR-001 – compromised server simulation${N}   $(now) UTC"
echo "  victim ${VICTIM} (${VIP}, hub private subnet)  →  target Spoke A host ${TARGET}"
mark "T0 – simulation starts on ${VICTIM} (${VIP})" "ir-simulate.sh"

step "1 · Reconnaissance: port scan of Spoke A" \
     "scans ~80 ports on ${TARGET} to find services to attack" \
     "Spoke A security group REJECTs → flow logs → alarm secnet-spoke_a-rejected-flows-spike (≈5 min)"
ssm_run "$VICTIM" "
ports=\"21 22 23 25 53 110 135 139 143 389 443 445 465 587 993 995 1433 1521 2049 2375 3306 3389 5432 5900 6379 8080 8443 9200 11211 27017 \$(seq -s ' ' 1000 1049)\"
for p in \$ports; do (timeout 2 bash -c \"</dev/tcp/${TARGET}/\$p\" 2>/dev/null && echo open || echo closed) & done > /tmp/scan.txt; wait
echo \"scanned \$(wc -l < /tmp/scan.txt) ports: \$(grep -c open /tmp/scan.txt) open, \$(grep -c closed /tmp/scan.txt) closed/filtered\""
mark "Step 1 – port scan of Spoke A ${TARGET} (~80 ports)" "ir-simulate.sh"

step "2 · Lateral movement: SSH attempts" \
     "tries to log in to ${TARGET} over SSH, 10 times" \
     "flow logs dstport 22 → alarm secnet-spoke_a-ssh-attempt (≈5 min)"
ssm_run "$VICTIM" "
ok=0; for i in \$(seq 1 10); do timeout 2 bash -c \"</dev/tcp/${TARGET}/22\" 2>/dev/null && ok=\$((ok+1)); done
echo \"10 SSH connection attempts to ${TARGET}: \$ok succeeded\""
mark "Step 2 – 10 SSH attempts to ${TARGET}:22" "ir-simulate.sh"

step "3 · Command & control: call home" \
     "looks up GuardDuty's official test C2 domain (guarddutyc2activityb.com)" \
     "GuardDuty DNS analysis → Backdoor:EC2/C&CActivity.B!DNS (high) → EventBridge → email (≈5–20 min)"
ssm_run "$VICTIM" "
for i in 1 2 3; do getent hosts guarddutyc2activityb.com >/dev/null && r=resolved || r='no answer'; done
echo \"guarddutyc2activityb.com looked up 3 times: \$r\""
mark "Step 3 – DNS lookups of guarddutyc2activityb.com (C2 test domain)" "ir-simulate.sh"

step "4 · Exfiltration attempt to a blocklisted domain" \
     "tries to reach c2.evil-demo.example to send data out" \
     "DNS Firewall blocks the lookup before any connection exists (prevention, D12)"
ssm_run "$VICTIM" 'python3 - <<"PY"
import socket, struct, random
q = struct.pack(">HHHHHH", random.randint(0, 65535), 0x0100, 1, 0, 0, 0)
q += b"".join(bytes([len(p)]) + p.encode() for p in "c2.evil-demo.example".split(".")) + b"\0" + struct.pack(">HH", 1, 1)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3); s.sendto(q, ("169.254.169.253", 53)); r = s.recv(512)
print("c2.evil-demo.example: " + ("BLOCKED by DNS Firewall" if b"dns-firewall-blocked" in r else "NOT blocked"))
PY'
mark "Step 4 – lookup of c2.evil-demo.example (blocklisted)" "ir-simulate.sh"

echo
echo "${B}Simulation finished${N} $(now) UTC. Timeline: ${TL}"
echo "${Y}What to watch next${N}"
echo "  ≈5 min   CloudWatch alarms → email (secnet-network-alerts): spoke_a rejected-flows spike, spoke_a SSH attempt"
echo "  ≈10 min  flow logs land in S3 → Athena queries 11 (port 22), 12 (port scan), 14 (host timeline: ${VIP})"
echo "  ≈5–20 min GuardDuty finding Backdoor:EC2/C&CActivity.B!DNS → email (secnet-security-findings)"
echo "  Then: preserve evidence (snapshot) BEFORE containment – see docs/runbooks/ir-runbook.md"
