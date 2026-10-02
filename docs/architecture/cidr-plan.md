# CIDR plan

Non-overlapping ranges are what make peering, TGW and VPN routing possible.

| Network | CIDR | Connected by | Internet |
|---|---|---|---|
| Hub VPC | 10.0.0.0/16 | – | IGW (public), NAT (private) |
| Spoke A | 10.1.0.0/16 | VPC peering | none |
| Spoke B | 10.2.0.0/16 | Transit Gateway | none |
| Office (simulated) | 192.168.0.0/16 | Site-to-Site VPN → TGW | own IGW for the router |

## Subnets

| VPC | Subnet | AZ | CIDR | Tier | Holds |
|---|---|---|---|---|---|
| Hub | secnet-public-1 | eu-west-1a | 10.0.1.0/24 | public | ALB, NAT |
| Hub | secnet-public-2 | eu-west-1b | 10.0.2.0/24 | public | ALB |
| Hub | secnet-private-1 | eu-west-1a | 10.0.11.0/24 | private | web EC2, RDS, TGW ENI, endpoints, victim |
| Hub | secnet-private-2 | eu-west-1b | 10.0.12.0/24 | private | RDS standby subnet, TGW ENI |
| Spoke A | secnet-spoke-a-subnet | eu-west-1a | 10.1.1.0/24 | private | test instance, SSM endpoints |
| Spoke B | secnet-spoke-b-subnet | eu-west-1a | 10.2.1.0/24 | private | test instance, NLB, SSM endpoints, TGW ENI |
| Office | secnet-onprem-subnet | eu-west-1a | 192.168.1.0/24 | public | strongSwan router |

AWS reserves 5 addresses in every subnet (first four + last), so a /24 has 251 usable IPs.
