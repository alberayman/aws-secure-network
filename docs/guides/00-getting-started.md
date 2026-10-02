# Guide 0: Getting started (everyone reads this first)

Every task in Guides 1 to 4 is done twice:

1. **Console first.** Click through it in the AWS console so you understand every setting. Take screenshots.
2. **Delete what you clicked** (or you will have duplicates and name clashes).
3. **Terraform second.** Switch the same thing on in code, run `plan`, read it, run `apply`, then test it.

Who does what: we are six students, no job titles. Each member leads one workstream (see `docs/team-roles.md`):

| Member | Workstream |
|---|---|
| 1 | Networking |
| 2 | Servers and database |
| 3 | Hybrid connectivity |
| 4 | Edge and access security |
| 5 | Logging and incident response |
| 6 | Repo, CI and reporting |

---

## 0.1 AWS account safety (Member 6, day 1, 30 minutes)

### Console steps
1. Sign in as **root**. Top right > your name > **Security credentials** > **Assign MFA device** > Authenticator app. Scan, enter two codes. From now on root is only for billing emergencies.
2. **Billing and Cost Management** > **Billing preferences**: tick *Receive AWS Free Tier alerts* and *Receive CloudWatch billing alerts*.
3. **IAM** > **User groups** > **Create group** `project-team`, attach `AdministratorAccess`.
   - Acceptable only because this is a short-lived lab account. In a company account you would use IAM Identity Center with least-privilege permission sets.
4. **IAM** > **Users** > **Create user** for each of the six members: tick *Provide user access to the AWS Management Console*, *I want to create an IAM user*, custom password, *must create a new password at next sign-in*. Add to `project-team`.
5. Each member signs in with the account's sign-in URL (IAM dashboard, right side) and adds **MFA** on their own user (IAM > Users > me > Security credentials > Assign MFA).
6. Region selector (top right): **Europe (Ireland) eu-west-1**. Always check it before you create anything. Exceptions: IAM, CloudFront and Route 53 are global; the WAF for CloudFront lives in **N. Virginia us-east-1**.

> **Free plan accounts.** AWS accounts created after 15 July 2025 start on a *free plan* with up to $200 credits. If a service refuses to start ("not available on the free plan"), Member 6 upgrades the account to the paid plan in Billing; remaining credits still apply. Budgets (0.2) protect you either way.

### Terraform
Nothing yet. IAM users stay manual: Terraform state would otherwise contain your colleagues' login details.

---

## 0.2 Budget alerts (Member 6, day 1)

### Console steps
1. **Billing and Cost Management** > **Budgets** > **Create budget** > *Use a template* > **Monthly cost budget**.
2. Name `secnet-monthly`, amount **50** USD, email: the team's shared email or Member 6's.
3. Create. Open it > **Alerts** > add thresholds at 25%, 50%, 80% actual and 100% forecasted.

### Terraform
Already written in `terraform/envs/dev/budget.tf`. When you apply Week 1 it creates the same budget, so **delete the console one first**.

---

## 0.3 Tools on every laptop (everyone, day 1)

| Tool | Install | Check it works |
|---|---|---|
| Git | git-scm.com | `git --version` |
| AWS CLI v2 | docs.aws.amazon.com/cli | `aws --version` |
| Terraform **1.10 or newer** | developer.hashicorp.com/terraform/install | `terraform version` |
| Session Manager plugin | docs.aws.amazon.com > Session Manager > Install plugin | `session-manager-plugin` |
| VS Code + *HashiCorp Terraform* extension | code.visualstudio.com | open a `.tf` file: syntax colours |

Create an access key: **IAM** > **Users** > you > **Security credentials** > **Create access key** > *Command Line Interface* > tick the warning > Create. Then on your laptop:

```bash
aws configure --profile secnet     # paste key + secret, region eu-west-1, output json
export AWS_PROFILE=secnet          # Windows PowerShell: $env:AWS_PROFILE="secnet"
aws sts get-caller-identity        # must print the account ID and YOUR user name
```

Rules: never paste keys in chat, code, screenshots or GitHub. Delete your key on the last day.

---

## 0.4 Remote state bucket (Member 6, day 1)

Terraform keeps a **state file**: its memory of what it built. Six people share one environment, so the state lives in S3 with locking, not on a laptop.

### Console steps
1. **S3** > **Create bucket**: name `secnet-tfstate-<ACCOUNT_ID>` (12-digit ID from the top-right menu), region eu-west-1.
2. **Block all public access**: ON. **Bucket Versioning**: Enable. **Default encryption**: SSE-S3. Create.

This bucket is the one thing created by hand and never managed by Terraform (a tool cannot safely store its own memory in something it might delete).

### Terraform
1. Open `terraform/envs/dev/versions.tf`, uncomment the `backend "s3"` block, put your bucket name in.
2. Commit that change (the bucket name is not a secret).
3. Every member then runs:
```bash
cd terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars   # set alert_email; this file is git-ignored
terraform init
```
`use_lockfile = true` makes Terraform write a lock object in S3 while someone runs `apply`; a second person gets *"Error acquiring the state lock"* instead of corrupting the state.

**Team rule:** everyone may run `plan`. Only one person runs `apply` at a time, and says so in the team chat first.

---

## 0.5 Terraform in six commands

```bash
terraform init       # download the AWS provider, connect to the S3 state
terraform fmt -recursive   # tidy the formatting (CI fails if you skip this)
terraform validate   # syntax and reference check, no AWS calls
terraform plan       # what WOULD change. Read the last line: "Plan: X to add, Y to change, Z to destroy"
terraform apply      # make the change (type yes)
terraform output     # print URLs, IDs and IPs you need for testing
```

Vocabulary: a **resource** is one AWS thing; a **module** is a folder of resources (ours: `vpc`, `compute`, `connectivity`, `edge`, `monitoring`); a **variable** is an input; an **output** is a value printed or passed to another module; **state** is Terraform's memory.

**A surprise "to destroy" in a plan means stop and ask the team.**

---

## 0.6 Week switches: how this repo saves money

All code for all four weeks is already in `terraform/envs/dev/`. What gets built is controlled by switches in your `terraform.tfvars`:

| Switch | Week | Builds | Rough cost while on |
|---|---|---|---|
| (always on) | 1 | Hub VPC, EC2, ALB, RDS, CloudTrail, S3 + CloudWatch flow logs, network alarms, budget | ~$0.10/h |
| `enable_nat` | 1+ | NAT gateway (private hosts reach the internet) | ~$0.05/h |
| `enable_hybrid` | 2 | Spokes, peering, Transit Gateway, endpoints, PrivateLink, test hosts | ~$0.25/h |
| `enable_vpn` | 2 | Simulated office + Site-to-Site VPN | ~$0.07/h |
| `enable_client_vpn` (+ 2 cert ARNs) | 2 lab | Client VPN endpoint for remote users | ~$0.15/h while connected |
| `enable_edge` | 3 | CloudFront, S3 site, WAF, Route 53, WAF alarm | ~$11/month prorated |
| `enable_ir` / `isolate_victim` | 4 | Victim host, snapshot, quarantine SG / the containment drill | ~$0.02/h |
| `enable_mirroring` | 4 | Traffic Mirroring target + session | ~$0.03/h |

Turn a switch to `true` > `plan` > `apply`. Turn it back to `false` > `plan` (shows only destroys) > `apply`. At the end of each session: `make sleep` (turns off NAT, hybrid, VPN, Client VPN, mirroring).

---

## 0.7 Git workflow (everyone)

```bash
git clone https://github.com/<team-org>/aws-secure-network.git && cd aws-secure-network
git checkout -b week1/m2-alb             # branch per task: week/member-topic
# ... edit ...
terraform fmt -recursive terraform
git add -A && git commit -m "feat(compute): ALB health check every 15s"
git push -u origin week1/m2-alb
```
On GitHub: **Compare & pull request** > fill the template (paste the `plan` summary, never secrets) > ask one teammate to review > wait for the green **terraform-ci** check > **Squash and merge**. Then `git checkout main && git pull`.

Member 6 sets on GitHub: **Settings > Branches > Add rule** for `main`: require a pull request, 1 approval, status checks to pass. **Settings > Code security**: secret scanning and push protection ON.

---

## 0.8 Evidence habit

Each task ends with **Check it worked**. Screenshot every check and save it as `docs/evidence/weekN/<member>-<what>.png`. Write the command, expected result and actual result in `docs/weekN/README.md`. This is what the panel grades.
