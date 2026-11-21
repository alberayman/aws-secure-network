#!/usr/bin/env bash
# End-of-session cost saver. Overrides the expensive switches for this one apply.
# Your terraform.tfvars is NOT changed: next session, plan + apply turns them back on.
set -euo pipefail
cd "$(dirname "$0")/../terraform/envs/dev"
# One normal plan (no -target): Terraform works out everything that depends on the switches,
# and the hub monitoring (flow logs, alarms, CloudTrail) is never touched.
terraform plan -no-color -out sleep.tfplan \
  -var enable_compute=false \
  -var enable_nat=false \
  -var enable_hybrid=false \
  -var enable_vpn=false \
  -var enable_edge=false \
  -var enable_client_vpn=false \
  -var enable_ir=false \
  -var enable_mirroring=false | tee sleep.txt
echo
grep -E "^Plan:" sleep.txt
read -r -p "Apply this plan (only destroys expected)? [y/N] " ok
if [[ "$ok" == "y" ]]; then
  terraform apply sleep.tfplan
  echo "Sleeping: web tier, NAT, spokes, TGW, VPN, Client VPN and IR hosts removed. Edge (CloudFront, WAF, private DNS) removed too. Hub VPC, monitoring, CloudTrail and budget stay."
else
  echo "Nothing changed."
fi
rm -f sleep.tfplan
