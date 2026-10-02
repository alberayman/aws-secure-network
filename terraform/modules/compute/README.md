# compute module

**Owners:** Member 2 (Servers and database: EC2/ALB/RDS) · Member 4 (Edge and access security: `security_groups.tf`, `iam.tf`) · **Week:** 1

Private EC2 web server (nginx, IMDSv2, encrypted disk, SSM only), internet-facing ALB,
private encrypted RDS MySQL with the password managed by Secrets Manager, and the SG chain
`Internet → ALB:80 → EC2:80 → RDS:3306`.

| Input | Purpose |
|---|---|
| `name`, `vpc_id`, `public_subnet_ids`, `private_subnet_ids` | from the vpc module |
| `internal_cidrs` | networks allowed to ping the web host (Week 2) |
| `instance_type` | default `t3.micro` |

Outputs: `alb_dns_name`, `alb_zone_id`, `alb_arn`, `web_instance_id`, `web_private_ip`,
`ec2_profile_name`, `ec2_role_name`, `ec2_sg_id`, `db_endpoint`, `db_secret_arn`.

**Test:** ALB DNS shows the page · SSM session works · `curl <private-ip>` from a laptop times out ·
MySQL connects from the web host only.
**Cost:** ALB ≈ $0.025/h, RDS db.t3.micro ≈ $0.02/h (free-tier credit may cover it).
