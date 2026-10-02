# connectivity module

**Owner:** Member 3 (Hybrid connectivity) · **Week:** 2

Spoke A (`10.1.0.0/16`) over **VPC peering**, Spoke B (`10.2.0.0/16`) over **Transit Gateway**,
and a simulated office (`192.168.0.0/16`) with a **strongSwan** router connected by
**Site-to-Site VPN** to the TGW. Spokes have no internet; they are managed through the SSM
interface endpoints in `envs/dev/endpoints.tf`.

Inputs: `name`, `az`, `hub_vpc_id`, `hub_vpc_cidr`, `hub_private_subnet_ids`,
`hub_private_route_table_id`, `instance_profile_name`, `spokes`, `onprem_cidr`.

Outputs: `spoke_vpc_ids`, `spoke_subnet_ids`, `spoke_cidrs`, `onprem_vpc_id`, `onprem_instance_id`,
`strongswan_public_ip`, `tgw_id`, `vpn_connection_id`, `vpn_tunnel1_address`, `vpn_tunnel1_psk` (sensitive).

**Manual step that stays manual:** configuring strongSwan from the downloaded VPN config (Guide 2.2 D).
**Cost (per hour, eu-west-1, approx.):** TGW attachments 3 × $0.05 · VPN $0.05 · EIP $0.005 · EC2.
Destroy the same day: `make destroy-expensive`.
