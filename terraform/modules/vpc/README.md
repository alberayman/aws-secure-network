# vpc module

**Owner:** Member 1 (Networking) · **Week:** 1 (NACL update in Week 2)

Hub VPC with 2 public + 2 private subnets in 2 AZs, Internet Gateway, one NAT Gateway,
public/private route tables, a locked-down default security group and a private-tier NACL.

| Input | Type | Purpose |
|---|---|---|
| `name` | string | Name prefix (`secnet`) |
| `vpc_cidr` | string | `10.0.0.0/16` |
| `azs` | list(string) | Two AZs |
| `public_subnet_cidrs` | list(string) | `10.0.1.0/24`, `10.0.2.0/24` |
| `private_subnet_cidrs` | list(string) | `10.0.11.0/24`, `10.0.12.0/24` |
| `extra_allowed_cidrs` | list(string) | Spokes + on-prem allowed through the NACL (Week 2) |
| `enable_nat` | bool | `false` removes the NAT gateway to save money (private hosts lose internet) |

| Output | Used by |
|---|---|
| `vpc_id`, `vpc_cidr` | every other module |
| `public_subnet_ids` | ALB |
| `private_subnet_ids` | EC2, RDS, TGW attachment, endpoints |
| `private_route_table_id` | connectivity (spoke/VPN routes), S3 gateway endpoint |
| `nat_gateway_id` | cost teardown |

**Test:** VPC > Resource map matches `docs/architecture/cidr-plan.md`; `terraform output` lists the IDs.
**Cost:** NAT Gateway ≈ $0.048/h + data. Set `enable_nat = false` after each session.
