# Secure AWS Network Architecture & Hybrid Connectivity

**DEPI – Digital Egypt Pioneers Initiative** · AWS Security & Cloud Computing track · Graduation project (Project 2)
**Group:** ONL5_ISS11_G1 · 6 students · 4 weeks · built with Terraform in `eu-west-1`

A production-style AWS network built as code: a private three-tier app, hub-and-spoke connectivity with a
Site-to-Site VPN to a simulated office, a WAF-protected CloudFront edge, and a full incident-response drill.

```
Users ── HTTPS ──► CloudFront + WAF ──► S3 (private, OAC)
  │
  └── HTTP ──► ALB (public subnets) ──► EC2 (private, SSM only) ──► RDS MySQL (private, encrypted)
                     Hub VPC 10.0.0.0/16
                        ├── peering ── Spoke A 10.1.0.0/16
                        └── Transit Gateway ── Spoke B 10.2.0.0/16 (PrivateLink service)
                                         └── IPsec VPN ── Office 192.168.0.0/16 (strongSwan)
Remote users: Client VPN (mutual TLS) ── hub only
Monitoring: CloudTrail · VPC Flow Logs → S3 → Athena + → CloudWatch alarms (scan, SSH) → SNS · WAF logs · Traffic Mirroring
```

## Team

We are six students; each leads one workstream (details in [`docs/team-roles.md`](docs/team-roles.md)).

| # | Name | GitHub | Workstream |
|---|---|---|---|
| 1 | Taghride Ahmed Gadelrab Abdelhafez |  | Networking |
| 2 | Ahlam Reda Abdelmonim Ahmed |  | Servers and database |
| 3 | Mohamed AbdElMeged Hagag |  | Hybrid connectivity |
| 4 | Asmaa Salah Elsayed Abbas |  | Edge and access security |
| 5 | Ahmed Abd El Haleem El Araby |  | Logging and incident response |
| 6 | Alber Ayman Mokhtar Fouad | [@alberayman](https://github.com/alberayman) | Repo, CI and reporting |

## Start here

1. [Guide 0 – Getting started](docs/guides/00-getting-started.md) (account safety, tools, state, Git)
2. [Week 1 – VPC core](docs/guides/week1-vpc-core.md)
3. [Week 2 – Connectivity & hybrid](docs/guides/week2-connectivity.md)
4. [Week 3 – Edge security](docs/guides/week3-edge-security.md)
5. [Week 4 – Detection & IR](docs/guides/week4-detection-ir.md)

Every task: **console first** (learn it) → delete → **Terraform** (deliver it) → **check it worked** (evidence).

## Repo layout

```
terraform/
  modules/        vpc · compute · connectivity · edge · monitoring (one per workstream)
  envs/dev/       wires the modules + one file per extra feature, week switches in terraform.tfvars
docs/
  guides/         step-by-step, console then Terraform
  week1..week4/   deliverables per week (fill in)
  architecture/   CIDR plan, route tables, diagrams
  runbooks/       incident response
  evidence/       screenshots per week
scripts/          sleep (cost saving) helper
.github/          CI (fmt, validate, TFLint, Checkov), PR template, CODEOWNERS
```

## How to run

```bash
cd terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars    # set alert_email, then switch weeks on
terraform init
terraform plan -out tf.plan && terraform apply tf.plan
terraform output
```

| Switch in `terraform.tfvars` | Week | What it builds |
|---|---|---|
| *(always)* | 1 | VPC, EC2, ALB, RDS, CloudTrail, log bucket, Athena, CloudWatch network alarms, budget |
| `enable_nat` | 1+ | NAT gateway |
| `enable_hybrid` | 2 | spokes, peering, TGW, SSM endpoints, PrivateLink, spoke tests, Flow Logs on spokes |
| `enable_vpn` | 2 | simulated office + Site-to-Site VPN |
| `enable_client_vpn` | 2 (lab) | Client VPN endpoint, mutual-TLS certificates (Guide 2.7) |
| `enable_edge` | 3 | CloudFront, S3 site, WAF, Route 53, WAF logs + alarm |
| `enable_ir`, `isolate_victim`, `enable_mirroring` | 4 | victim, quarantine drill, Traffic Mirroring |

End every session with **`make sleep`** (turns off NAT, hybrid, VPN, Client VPN and mirroring). Final day: `terraform destroy`.

## Deliverables (booklet Project 2)

| Week | Deliverable | Where |
|---|---|---|
| 1 | VPC design · subnet/CIDR plan · EC2/ALB/RDS · SG/NACL rules · architecture diagram · connectivity tests | [`docs/week1`](docs/week1/README.md) |
| 2 | Hub-and-spoke/TGW diagram · peering/endpoints · VPN configuration · route tables · hybrid test report | [`docs/week2`](docs/week2/README.md) |
| 3 | CloudFront + S3 lab · WAF rule set · DDoS mitigation plan · edge architecture · Route 53/health check design | [`docs/week3`](docs/week3/README.md) |
| 4 | Flow log queries · detection use cases · IR runbook · evidence notes · final report | [`docs/week4`](docs/week4/README.md), [`docs/final-report.md`](docs/final-report.md) |

## Security rules

MFA everywhere · no SSH (SSM only) · IMDSv2 · encryption at rest · least-privilege SG chaining ·
no secrets or state in Git (secret scanning + push protection on) · see [`CONTRIBUTING.md`](CONTRIBUTING.md).
