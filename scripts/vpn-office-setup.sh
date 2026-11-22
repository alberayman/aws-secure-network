#!/usr/bin/env bash
# Configure the simulated office router (strongSwan) for Site-to-Site VPN tunnel 1, over SSM.
#
#   make vpn-setup
#
# Run after every build with enable_vpn = true (the router is a fresh instance each time).
# The pre-shared key is NOT passed in the command: the router reads it from Parameter Store
# (SecureString) with its own IAM role, so the key never appears in SSM history, CloudTrail,
# the terminal, a chat or the repo. Only tunnel 1 is configured (lab); tunnel 2 stays DOWN.

set -u
cd "$(dirname "$0")/.." || exit 1
TFDIR=terraform/envs/dev
REGION=eu-west-1
P="--profile ${AWS_PROFILE:-secnet} --region $REGION"
out() { terraform -chdir="$TFDIR" output -raw "$1" 2>/dev/null; }

SW=$(out strongswan_instance_id); EIP=$(out strongswan_public_ip)
T1=$(out vpn_tunnel1_address); PARAM=$(out vpn_psk_parameter); VPN=$(out vpn_connection_id); WEBIP=$(out web_private_ip)
for v in SW EIP T1 PARAM VPN; do [ -n "${!v}" ] || { echo "Missing output for $v: is enable_vpn = true and applied?"; exit 1; }; done

echo "Office router ${SW}: configuring tunnel 1 (key read on the router from ${PARAM}) …"

# wait until SSM sees the router
for i in $(seq 1 30); do
  st=$(aws ssm describe-instance-information $P --filters "Key=InstanceIds,Values=$SW" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null)
  [ "$st" = "Online" ] && break; sleep 10
done
[ "$st" = "Online" ] || { echo "Router not Online in SSM after 5 min (status: $st)"; exit 1; }

REMOTE=$(cat <<EOS
set -e
cloud-init status --wait >/dev/null 2>&1 || true
command -v ipsec >/dev/null || { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq strongswan strongswan-starter; }
command -v aws >/dev/null || snap install aws-cli --classic >/dev/null
cat > /etc/ipsec.conf <<'CONF'
config setup
  charondebug="ike 1, knl 1, cfg 0"
conn %default
  keyexchange=ikev1
  ike=aes128-sha1-modp1024!
  esp=aes128-sha1-modp1024!
  ikelifetime=8h
  lifetime=1h
  dpddelay=10s
  dpdtimeout=30s
  dpdaction=restart
  authby=secret
  auto=start
  type=tunnel
  left=%defaultroute
  leftsubnet=192.168.0.0/16
  rightsubnet=10.0.0.0/8
conn tunnel1
  leftid=${EIP}
  right=${T1}
CONF
umask 077
PSK=\$(aws ssm get-parameter --region ${REGION} --name ${PARAM} --with-decryption --query Parameter.Value --output text)
printf '%s %s : PSK "%s"\n' "${EIP}" "${T1}" "\$PSK" > /etc/ipsec.secrets
unset PSK
chmod 600 /etc/ipsec.secrets
ipsec restart >/dev/null
sleep 15
ipsec status | grep -q 'tunnel1.*ESTABLISHED' && echo "tunnel1 ESTABLISHED" || { echo "tunnel1 NOT established"; ipsec status | head -5; }
ok=FAIL; for i in 1 2 3 4 5 6; do ping -c2 -W2 ${WEBIP:-10.0.11.96} >/dev/null 2>&1 && { ok=OK; break; }; sleep 10; done; echo "ping hub web server \$ok"
EOS
)

b64=$(printf '%s' "$REMOTE" | base64 | tr -d '\n')
cid=$(aws ssm send-command $P --instance-ids "$SW" --document-name AWS-RunShellScript \
      --comment "office router VPN setup (no secrets in this command)" --timeout-seconds 600 \
      --parameters "{\"commands\":[\"echo $b64 | base64 -d | bash\"]}" --query Command.CommandId --output text) || exit 1
for i in $(seq 1 90); do
  sleep 5
  st=$(aws ssm get-command-invocation $P --command-id "$cid" --instance-id "$SW" --query Status --output text 2>/dev/null)
  case "$st" in Success|Failed|TimedOut|Cancelled) break ;; esac
done
aws ssm get-command-invocation $P --command-id "$cid" --instance-id "$SW" --query StandardOutputContent --output text | sed 's/^/  /'
up=$(aws ec2 describe-vpn-connections $P --vpn-connection-ids "$VPN" --query 'length(VpnConnections[0].VgwTelemetry[?Status==`UP`])' --output text)
echo "AWS side: tunnels UP = $up (1 expected; AWS can take ~1 min to report)"
