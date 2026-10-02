#!/usr/bin/env bash
# End-of-session cost saver. Overrides the expensive switches for this one apply.
# Your terraform.tfvars is NOT changed: next session, plan + apply turns them back on.
set -euo pipefail
cd "$(dirname "$0")/../terraform/envs/dev"
terraform plan -out sleep.tfplan \
  -var enable_nat=false \
  -var enable_hybrid=false \
  -var enable_vpn=false \
  -var enable_mirroring=false
echo
read -r -p "Apply this plan (only destroys expected)? [y/N] " ok
if [[ "$ok" == "y" ]]; then
  terraform apply sleep.tfplan
  echo "Sleeping: NAT, spokes, TGW, VPN and mirroring removed. Week 1 core, edge and IR hosts stay."
else
  echo "Nothing changed."
fi
rm -f sleep.tfplan
