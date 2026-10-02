# Week 1: VPC core architecture (step by step)

**Goal:** a three-tier app (ALB → EC2 → RDS) in a private, segmented VPC, with no SSH anywhere, plus logging and cost guardrails.
**Gate to pass:** the ALB page loads in a browser, a direct connection to EC2 fails, and RDS answers only from the web server.

Order: **1.1** first (everyone needs the VPC) → **1.2** and **1.3** in parallel → **1.4** → **1.5** runs from day 1.

| Task | Member | Terraform files |
|---|---|---|
| 1.1 VPC, subnets, NAT, NACL | 1 Networking | `modules/vpc/*` |
| 1.2 EC2, ALB, RDS | 2 Servers and database | `modules/compute/main.tf`, `iam.tf` |
| 1.3 Security groups, IAM | 4 Edge and access security | `modules/compute/security_groups.tf`, `iam.tf` |
| 1.4 CloudTrail, log bucket, Athena | 5 Logging and IR | `modules/monitoring/main.tf` |
| 1.5 Repo, state, CI, budget | 6 Repo, CI and reporting | `envs/dev/versions.tf`, `budget.tf`, `.github/` |
| 1.6 Bastion vs SSM (comparison + optional lab) | 4 (with 2) | none (console lab) |
| Week 1 apply | one person (agreed in chat) | `envs/dev/main.tf` |

---

## 1.1 Member 1: CIDR plan, VPC, subnets, NAT, NACL

### Console steps
1. Fill `docs/architecture/cidr-plan.md` **before** building and share it:
   hub `10.0.0.0/16`; public `10.0.1.0/24` (AZ a), `10.0.2.0/24` (AZ b); private `10.0.11.0/24` (AZ a), `10.0.12.0/24` (AZ b).
   Reserved for Week 2: Spoke A `10.1.0.0/16`, Spoke B `10.2.0.0/16`, office `192.168.0.0/16`. Ranges must never overlap or routing breaks.
2. **VPC** > **Create VPC** > **VPC and more**:
   - Name tag auto-generation `secnet`, IPv4 CIDR `10.0.0.0/16`, no IPv6.
   - Number of AZs **2**, public subnets **2**, private subnets **2**. Expand *Customize subnets CIDR blocks* and type the four CIDRs above.
   - NAT gateways **In 1 AZ** (one NAT ≈ $1.15/day; one per AZ is the production choice).
   - VPC endpoints **None** (Week 2). DNS hostnames ✔, DNS resolution ✔.
   - **Create VPC**, then open **Resource map**: 4 subnets, 2+ route tables, IGW, NAT. Screenshot it.
3. **Route tables**: public table → `0.0.0.0/0` → `igw-…`. Private table → `0.0.0.0/0` → `nat-…`. Note them in your route table doc.
4. **Network ACLs** > **Create network ACL** `secnet-private-nacl` in the VPC. NACLs are **stateless**, so return traffic needs its own rule.
   - Inbound: rule 100 *All traffic* from `10.0.0.0/16` allow; 110 *Custom TCP* 1024-65535 from `0.0.0.0/0` allow (replies through the NAT); 120 *Custom UDP* 1024-65535 from `0.0.0.0/0` allow (DNS/NTP replies).
   - Outbound: rule 100 *All traffic* to `0.0.0.0/0` allow.
   - **Subnet associations** > Edit > tick both private subnets.
5. **Security groups** > the VPC's **default** SG > remove all its inbound and outbound rules (nothing should ever use it).

**Delete it all before Terraform:** VPC > select `secnet-vpc` > Actions > **Delete VPC** (it deletes subnets, routes, IGW; delete the NAT gateway and release its Elastic IP first if it complains).

### Terraform (`terraform/modules/vpc/`)
Read the files in this order and match each block to a console step:

| Block in `main.tf` | Console step it replaces |
|---|---|
| `aws_vpc.this` | VPC + DNS settings |
| `aws_default_security_group.this` | step 5, empties the default SG |
| `aws_internet_gateway.this` | IGW (created by "VPC and more") |
| `aws_subnet.public` / `aws_subnet.private` (`count` = one per CIDR) | the four subnets |
| `aws_eip.nat` + `aws_nat_gateway.this` (`count = var.enable_nat ? 1 : 0`) | NAT in 1 AZ |
| `aws_route_table.*`, `aws_route.private_default`, `*_association` | step 3 |
| `aws_network_acl.private` | step 4; `dynamic "ingress"` adds the Week 2 networks |

How it is called: `terraform/envs/dev/main.tf` → `module "vpc"` passes the CIDRs above and picks the first two AZs from `data.aws_availability_zones`.

### Check it worked
- VPC > **Resource map** looks like your diagram.
- `terraform output` and `aws ec2 describe-subnets --filters Name=tag:Project,Values=secure-network --query "Subnets[].{CIDR:CidrBlock,AZ:AvailabilityZone}" --output table`.
- Draw the architecture diagram (draw.io, AWS icon set) and save it as `docs/architecture/week1.png`.

### Cost note
To pause the NAT overnight set `enable_nat = false` and apply (private hosts lose internet until you set it back).

---

## 1.2 Member 2: EC2, ALB, RDS

### Console steps
**A. Instance role (so nobody ever needs SSH)**
1. **IAM** > **Roles** > **Create role** > *AWS service* > **EC2** > attach `AmazonSSMManagedInstanceCore` > name `secnet-ec2-role`.

**B. Web server in a private subnet**
1. **EC2** > **Launch instance**: name `secnet-web`, AMI **Amazon Linux 2023**, type `t3.micro`, Key pair: **Proceed without a key pair**.
2. Network settings > Edit: VPC `secnet-vpc`, subnet **private** AZ a, **Auto-assign public IP: Disable**, select existing SG `secnet-ec2-sg` (from 1.3; create a temporary one if 1.3 is not ready).
3. Advanced details: IAM instance profile `secnet-ec2-role`; **Metadata version: V2 only (token required)**; User data:
```bash
#!/bin/bash
dnf install -y nginx
echo "<h1>secnet web server</h1><p>$(hostname)</p>" > /usr/share/nginx/html/index.html
systemctl enable --now nginx
```
4. Launch, wait 3 minutes, select it > **Connect** > **Session Manager** > Connect. Run `curl -s localhost`.

**C. Application Load Balancer**
1. **EC2** > **Target groups** > Create: *Instances*, name `secnet-tg`, HTTP 80, VPC `secnet-vpc`, health check `/`. Register `secnet-web` on port 80.
2. **Load balancers** > Create > **Application Load Balancer**: `secnet-alb`, Internet-facing, IPv4, VPC `secnet-vpc`, both **public** subnets, SG `secnet-alb-sg`, listener HTTP:80 → `secnet-tg`.
3. Wait for **Active**, paste the DNS name in a browser.

**D. RDS MySQL**
1. **RDS** > **Subnet groups** > Create `secnet-db-subnets` with both **private** subnets.
2. **Databases** > **Create database** > Standard create > **MySQL** > template **Free tier** (or Sandbox). Identifier `secnet-db`, master user `admin`, **Credentials management: Managed in AWS Secrets Manager**. `db.t3.micro`, 20 GiB. Connectivity: VPC `secnet-vpc`, subnet group `secnet-db-subnets`, **Public access: No**, SG `secnet-rds-sg`. Additional configuration: initial database name `appdb`, encryption ✔. Create (≈10 minutes).

**Delete before Terraform:** RDS (no final snapshot), ALB, target group, instance, role.

### Terraform (`terraform/modules/compute/`)
| File / block | What it does |
|---|---|
| `iam.tf` | the SSM-only role and instance profile (step A) |
| `main.tf` `data.aws_ssm_parameter.al2023` | always the latest Amazon Linux 2023 AMI, no hard-coded AMI ID |
| `aws_instance.web` | private subnet, `http_tokens = "required"` (IMDSv2), encrypted root disk, same user data |
| `aws_lb`, `aws_lb_target_group`, `aws_lb_listener`, `aws_lb_target_group_attachment` | step C; `drop_invalid_header_fields = true` is a free hardening |
| `aws_db_subnet_group`, `aws_db_instance` | step D; `manage_master_user_password = true` = AWS creates the password, it is **never in code or state** |
| `outputs.tf` | `alb_dns_name`, `web_private_ip`, `db_endpoint`, `db_secret_arn`, … |

### Check it worked
- Browser: `terraform output alb_url` shows *secnet web server*.
- Session Manager on the web server (no SSH rule exists anywhere).
- Database test from that session:
```bash
sudo dnf install -y mariadb105
aws secretsmanager get-secret-value --secret-id <db_secret_arn> --query SecretString --output text --region eu-west-1
mysql -h <db_endpoint> -u admin -p        # paste the password; you get mysql>
```
  If `get-secret-value` is denied, that is least privilege working: copy the password from **Secrets Manager** > secret > *Retrieve secret value* in the console instead.
- Record every command and result in `docs/week1/README.md`.

---

## 1.3 Member 4: security groups and least privilege

### Console steps
1. **EC2** > **Security groups** > create three groups in `secnet-vpc`:

| Group | Inbound | Outbound |
|---|---|---|
| `secnet-alb-sg` | HTTP 80 from `0.0.0.0/0` | **delete** "All traffic", add HTTP 80 to **`secnet-ec2-sg`** (select the group) |
| `secnet-ec2-sg` | HTTP 80 from **`secnet-alb-sg`** (the group, not an IP) · **no SSH** | All traffic (SSM + updates through NAT) |
| `secnet-rds-sg` | MySQL/Aurora 3306 from **`secnet-ec2-sg`** | delete "All traffic" (a database never starts connections) |

2. IAM check: `secnet-ec2-role` has only `AmazonSSMManagedInstanceCore`. Nothing has `AdministratorAccess` except human users.
3. Write `docs/week1/sg-nacl-matrix.md`: one row per allowed flow (source, destination, port, why) and one row per layer (SG = stateful, per instance; NACL = stateless, per subnet).

### Terraform (`terraform/modules/compute/security_groups.tf`)
- Each group is an `aws_security_group` with **no inline rules**; each rule is its own `aws_vpc_security_group_ingress_rule` / `_egress_rule`. This is the current AWS-provider best practice: one rule = one resource, so a change shows clearly in `plan`.
- `referenced_security_group_id` = "source is that group" (the console's *select group*).
- `ec2_icmp_internal` (for each of `10.0.0.0/8`, `192.168.0.0/16`) allows ping for the Week 2 test matrix.
- Not declaring an egress rule on `secnet-rds-sg` means **no outbound at all**.

### Check it worked (negative tests are the proof)
| Test | Command | Expected |
|---|---|---|
| Internet → EC2 directly | from your laptop `curl -m 5 http://<web_private_ip>` | timeout (private IP, no route) |
| Internet → ALB | browser to the ALB | page loads |
| EC2 → RDS | `mysql -h <db_endpoint> …` from the web server | connects |
| Remove `rds_from_ec2` temporarily | same `mysql` | timeout; put the rule back |
| Optional | **VPC > Reachability Analyzer**: IGW → web instance port 22 | *Not reachable*, names the blocking SG (≈$0.10 per analysis) |

---

## 1.4 Member 5: CloudTrail, log bucket, Athena workgroup

### Console steps
1. **S3** > Create bucket `secnet-logs-<ACCOUNT_ID>`: Block all public access ON, Versioning **Enable**, SSE-S3.
2. Bucket > **Management** > **Create lifecycle rule** `expire-logs`: all objects, expire current versions after **30** days, permanently delete noncurrent versions after **7** days.
3. **CloudTrail** > **Create trail** `secnet-trail`: *Use existing S3 bucket* → the logs bucket (the console writes the bucket policy), **Log file validation: Enabled**, SSE-KMS off for the lab (SSE-S3). Events: **Management events** read + write. Create. (A trail is multi-region by default.)
4. **Athena** > **Workgroups** > Create `secnet`: query result location `s3://secnet-logs-<ACCOUNT_ID>/athena-results/`, **Override client-side settings** ✔.

**Delete before Terraform:** the trail, the workgroup, empty + delete the bucket.

### Terraform (`terraform/modules/monitoring/main.tf`)
| Block | Why it matters |
|---|---|
| `aws_s3_bucket.logs` + public access block + ownership controls + SSE + versioning + lifecycle | the private, tamper-resistant evidence store |
| `aws_s3_bucket_policy.logs` | **one** policy for every writer: TLS-only deny, CloudTrail (scoped by `aws:SourceArn`) and VPC Flow Logs (scoped by `aws:SourceAccount`). If the console added statements instead, the next `apply` would silently remove them. |
| `aws_cloudtrail.this` | multi-region, global events, **log file validation** (digest files prove logs were not edited: chain of custody in Week 4) |
| `aws_athena_workgroup.this` | Week 4 queries run here, results encrypted |
| `flowlogs.tf` | Week 2 (hub flow log already starts in Week 1) |
| `athena.tf` | Week 4 saved queries |

### Check it worked
Create any security group in the console, wait 5 to 15 minutes: **CloudTrail** > **Event history** shows `CreateSecurityGroup` with your user name. S3 shows `AWSLogs/<account>/CloudTrail/eu-west-1/…`. Screenshot both.

---

## 1.5 Member 6: repo, state, CI, budget

### Console steps
1. Guide 0 steps 0.1, 0.2, 0.4 (MFA, users, budget, state bucket).
2. **GitHub**: create the repo `aws-secure-network` (private until the presentation), push this folder (README → *Publish the repo*). Settings > Collaborators: add the five teammates. Branch protection + secret scanning as in Guide 0.7.
3. **Actions** tab: open a test pull request, confirm `terraform-ci` runs both jobs (fmt/validate/TFLint and Checkov).

### Terraform
- `envs/dev/versions.tf`: the backend block (Guide 0.4), provider pin `~> 5.80`, `default_tags` (every resource gets `Project`, `Group`, `ManagedBy`).
- `envs/dev/budget.tf`: the budget from 0.2 with four alerts.

### Week 1 apply (one person)
```bash
cd terraform/envs/dev
terraform init
terraform plan -out week1.tfplan        # read it: only "to add", nothing "to destroy"
terraform apply week1.tfplan
terraform output
```

### Check it worked
- CI green on a pull request; a direct push to `main` is refused.
- Budgets page shows `secnet-monthly`; the email recipient gets the confirmation.
- `docs/week1/README.md` filled: all six deliverables linked (VPC design, CIDR plan, EC2/ALB/RDS, SG/NACL rules, diagram, test results).

### Clean up at the end of each session
`make sleep` (switches off the NAT and anything from later weeks). RDS can also be **stopped** for up to 7 days from the console (*Actions > Stop temporarily*); Terraform will not fight that.

---

## 1.6 Member 4 (with Member 2): bastion host vs SSM Session Manager

The booklet asks for "bastion/SSM access". We **build SSM** (1.2). We **prove why** with a short bastion lab, then delete the bastion. The panel will ask why we have no bastion, so this section is that answer.

### The comparison (write it in `docs/week1/bastion-vs-ssm.md`)
| | Bastion host (jump box) | SSM Session Manager (our choice) | EC2 Instance Connect Endpoint |
|---|---|---|---|
| How you get in | SSH to a public EC2, then SSH on to private hosts | browser or `aws ssm start-session`, over HTTPS | SSH through an AWS-managed endpoint into the VPC |
| Open inbound ports | 22 on the bastion (internet-facing) + 22 from bastion to hosts | **none** | 22 from the endpoint only |
| Credentials | SSH keys to create, share, rotate, revoke | IAM users + MFA you already have | IAM + short-lived keys |
| Audit | bastion OS logs, easy to tamper with | every session in CloudTrail, optional full transcript to S3/CloudWatch | CloudTrail |
| Public IP needed | yes (bastion) | no | no |
| Extra cost | 1 EC2 running 24/7 | free (needs the NAT or VPC endpoints) | free |
| Patching | you patch the bastion | AWS-managed agent | AWS-managed |
| Verdict | legacy pattern, larger attack surface | ✅ best for this project | good when a tool truly needs SSH |

### Optional lab (console only, about 30 minutes, delete the same day)
1. **EC2** > **Key pairs** > Create `secnet-bastion-key` (RSA, `.pem`). It downloads once. Keep it **outside** the repo (`.gitignore` blocks `*.pem` anyway).
2. Find your public IP (`curl -s https://checkip.amazonaws.com`).
3. **Launch instance** `secnet-bastion`: Amazon Linux 2023, `t3.micro`, key `secnet-bastion-key`, **public** subnet 1, auto-assign public IP **Enable**, new SG `secnet-bastion-sg` with inbound **SSH 22 from `<your-ip>/32` only**. Never use `0.0.0.0/0` for SSH.
4. From your laptop: `chmod 400 secnet-bastion-key.pem && ssh -i secnet-bastion-key.pem ec2-user@<bastion-public-ip>`.
5. Show the risk: **CloudTrail** records only that the instance started. Who ran which command lives only in the bastion's own OS logs. Then compare it with **Session Manager** > **Session history**, which records every session, by IAM user, in CloudTrail.
6. **Delete** the instance, the SG and the key pair. Screenshot each step for the comparison doc.

We deliberately do **not** open port 22 from the bastion to the web server: that would break the "no SSH anywhere" rule the rest of the project is built and tested on (Week 4 alarms on any internal port 22 flow).

### Check it worked
The comparison table is filled in, the lab screenshots are taken (or a one-line note saying the team skipped the optional lab), and the bastion resources are deleted (EC2 > Instances shows none).
