# Run the project in your own AWS account (step by step)

This guide takes you from **nothing** to the **full project running and tested in your own AWS account**,
then shows how to switch it off. Follow the steps in order. Every command is run in a terminal.

> **Time:** about 2–3 hours the first time (most of it is waiting for AWS).
> **Cost:** about **$0.50 per hour** while everything is on, about **$0.02–0.05 per hour** after `make sleep`.
> Always finish a session with `make sleep` (step 12) and remove everything at the end (step 13).

---

## Step 1 – What you need

| You need | How to check |
|---|---|
| An AWS account where you are allowed to create resources (your own, not your employer's) | You can sign in to the AWS console |
| A computer with **macOS or Linux** (Windows: use **WSL**, Ubuntu) | – |
| Access to the GitHub repo `alberayman/aws-secure-network` (it is private: ask Alber to add your GitHub user) | You can open the repo page in your browser |

### Install the tools

**macOS** (with [Homebrew](https://brew.sh)):
```bash
brew install awscli git make
brew tap hashicorp/tap && brew install hashicorp/tap/terraform
```

**Ubuntu / WSL:**
```bash
sudo apt-get update && sudo apt-get install -y git make curl unzip dnsutils netcat-openbsd
# AWS CLI v2
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip && unzip -q awscliv2.zip && sudo ./aws/install
# Terraform: follow https://developer.hashicorp.com/terraform/install (Linux, apt)
```

**Check** (all four must print a version; Terraform must be **1.10 or newer**):
```bash
aws --version
terraform version
git --version
make --version
```

---

## Step 2 – Make your AWS account safe (15 minutes, console)

1. Sign in as **root** → top right, your name → **Security credentials** → **Assign MFA device**. Use an authenticator app.
2. **IAM** → **Users** → **Create user**, name for example `secnet-lab`. Attach the policy **AdministratorAccess**
   (fine for a personal lab account; never do this in a company account).
3. Open the new user → **Security credentials** → **Assign MFA device** (for console sign-in).
4. Same page → **Create access key** → *Command Line Interface (CLI)* → tick the confirmation → **Create**.
   You see an **Access key ID** and a **Secret access key**. Keep the window open for step 4.

> **Never** paste these keys into a chat, an email, a screenshot or the repo. If you leak one, delete it in IAM
> straight away and create a new one.

5. Top right of the console, choose the Region **Europe (Ireland) eu-west-1**.

---

## Step 3 – Get the code

```bash
cd ~                      # or any folder you like
git clone https://github.com/alberayman/aws-secure-network.git
cd aws-secure-network
```

**From now on, run every command from this folder.** Your prompt should end with `aws-secure-network %` or
`aws-secure-network $`. Most "file not found" errors come from being in the wrong folder.

---

## Step 4 – Connect the AWS CLI to your account

```bash
aws configure --profile secnet
```
Answer the four questions:

| Question | Answer |
|---|---|
| AWS Access Key ID | the key ID from step 2 |
| AWS Secret Access Key | the secret from step 2 |
| Default region name | `eu-west-1` |
| Default output format | `json` |

Tell Terraform and the scripts to use this profile (do this **in every new terminal window**):
```bash
export AWS_PROFILE=secnet
```

**Check:**
```bash
aws sts get-caller-identity
```
You should see your own account number and `user/secnet-lab`. Write the **12-digit account number** down;
below it is called `<ACCOUNT_ID>`.

---

## Step 5 – Pre-checks (avoid the two most common failures)

**a) VPC limit.** The project creates 4 VPCs; every account already has 1 default VPC; the default limit is 5.
That fits exactly, but ask for more room so nothing fails:
```bash
aws service-quotas request-service-quota-increase --service-code vpc --quota-code L-F678F1CE --desired-value 10
```
(Approval usually takes minutes to a day. You can continue meanwhile.)

**b) Services that may already be on in your account.** GuardDuty, AWS Config, Security Hub and the Session
Manager preferences can exist only once per account and Region. Check:
```bash
aws guardduty list-detectors
aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[].name'
aws securityhub describe-hub
aws ssm describe-document --name SSM-SessionManagerRunShell --query Document.Name
```

| Good result | Bad result: what to do |
|---|---|
| `"DetectorIds": []` | An ID is listed → set `enable_detection = false` in step 8 |
| `[]` | A recorder is listed → set `enable_detection = false` in step 8 |
| an error "not subscribed" | JSON with `HubArn` → set `enable_detection = false` in step 8 |
| an error "does not exist" | The document exists → ask Alber (it must be imported into Terraform first) |

**c) Brand-new accounts** can be blocked from creating load balancers for a while
(`OperationNotPermitted … does not support creating load balancers`). If you hit it in step 9, wait a few hours
and try again; it was temporary when it happened to us.

---

## Step 6 – Create your own Terraform state bucket (once)

Terraform keeps a record of what it built (the *state*) in an S3 bucket. Each person needs their own.
Replace `<ACCOUNT_ID>` with your number (4 commands):

```bash
B=secnet-tfstate-<ACCOUNT_ID>
aws s3api create-bucket --bucket $B --region eu-west-1 --create-bucket-configuration LocationConstraint=eu-west-1
aws s3api put-bucket-versioning --bucket $B --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket $B --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```
(S3 encrypts new objects by default.) **Keep this bucket private:** the state contains sensitive values such as the
VPN key.

---

## Step 7 – Initialise Terraform with your bucket

The code names Alber's bucket; this command points it at **yours** without changing any file:
```bash
terraform -chdir=terraform/envs/dev init -backend-config="bucket=secnet-tfstate-<ACCOUNT_ID>"
```
Expected: `Terraform has been successfully initialized!`

---

## Step 8 – Your settings file

```bash
cp terraform/envs/dev/terraform.tfvars.example terraform/envs/dev/terraform.tfvars
```
Open `terraform/envs/dev/terraform.tfvars` in any editor and set **your email** (alerts go there):
```hcl
alert_email = "you@example.com"
```
Leave the switches as they are for now (only the Week 1 parts on). **Never commit this file** (it is already in
`.gitignore`).

---

## Step 9 – Build in four stages

Each stage is the same routine. **Read the plan before you apply it.**

```bash
make plan     # shows what will be created/changed/destroyed, saves it to tf.plan
make apply    # builds exactly that plan
```

Rules for reading a plan:
- `+ create` is normal when you switch something on.
- **`- destroy` or `-/+ replace`: stop and understand why** before you apply.
- If the plan fails, nothing was changed. Read the error, fix, plan again.

### Stage 1 – Secure foundation (≈15 min)
Switches (already set in the example): `enable_compute = true`, `enable_nat = true`.
`make plan` → read → `make apply`.
**Then:** open your email and **confirm the AWS Notification "Subscription Confirmation"** messages that arrive
(alarms only reach you after you click them). Test:
```bash
make demo ARGS="--week 1 --auto"
```

### Stage 2 – Hybrid connectivity (≈20 min)
In `terraform.tfvars` set `enable_hybrid = true` and `enable_vpn = true`. `make plan` → read → `make apply`.
**Then configure the office VPN router** (fully automatic, no keys to copy):
```bash
make vpn-setup
```
Expected at the end: `tunnel1 ESTABLISHED`, `ping hub web server OK`, `tunnels UP = 1`. Test:
```bash
make demo ARGS="--week 2 --auto"
```

### Stage 3 – Edge protection (≈15 min, CloudFront is slow)
Set `enable_edge = true`. `make plan` → read → `make apply`. **Confirm the new SNS email** (topic `secnet-alerts`,
us-east-1). Open the project website: `open "$(terraform -chdir=terraform/envs/dev output -raw cloudfront_url)"`
(Linux: copy the address into a browser). Test:
```bash
make demo ARGS="--week 3 --auto"
```

### Stage 4 – Detection and incident response (≈15 min)
First look up the AWS managed DNS Firewall lists in your account:
```bash
aws route53resolver list-firewall-domain-lists --query "FirewallDomainLists[?ManagedOwnerName!=null].[Name,Id]" --output table
```
In `terraform.tfvars` add (use **your** IDs for *MalwareDomainList* and *BotnetCommandandControl*; set
`enable_detection = false` instead if step 5b said so):
```hcl
enable_detection              = true
dns_firewall_managed_list_ids = ["rslvr-fdl-…malware…", "rslvr-fdl-…botnet…"]
dns_firewall_managed_action   = "ALERT"   # switch to "BLOCK" after the full test passes
enable_ir                     = true
isolate_victim                = false
```
`make plan` → read → `make apply`. **Confirm the `secnet-security-findings` email.** Test:
```bash
make demo ARGS="--week 4 --auto"
```

---

## Step 10 – Run every test

```bash
make demo ARGS="--auto"
```
Each test prints **what it proves**, **where it runs**, **the command** and **the expected result**.
Expected summary: **35 passed** (T39 is skipped until you isolate the victim in step 11). A ❌ next to *Expected*
means we **want** it blocked: a block is a pass.

> After a full run you will get an email "ALARM: secnet-hub-ssh-attempt". That is test T21 probing port 22 on
> purpose; it is not an attack.

When everything passes you can switch the DNS Firewall to `"BLOCK"` (plan → apply → run the tests again).

---

## Step 11 – The incident drill (optional, ≈30 min)

1. **Attack:** `make ir-simulate` (it explains each step; press Enter to continue).
2. **Detect:** within ~5 minutes you get alarm emails and a GuardDuty email naming the victim instance.
3. **Investigate:** AWS console → **Athena** → workgroup `secnet` → *Saved queries* → run
   `01-create-flow-logs-table` once, then `15-victim-lateral-movement` (replace `10.0.11.X` with
   `terraform -chdir=terraform/envs/dev output -raw victim_private_ip`). Flow logs arrive in S3 about 10 minutes
   after the traffic.
4. **Preserve evidence** (before containment): follow "Preserve" in `docs/runbooks/ir-runbook.md`.
5. **Contain:** set `isolate_victim = true` → `make plan` → read (0 to destroy!) → `make apply` →
   `make demo ARGS="--only T39"`.
6. **Recover:** set `isolate_victim = false`, then
   `terraform -chdir=terraform/envs/dev plan -replace='aws_instance.victim[0]' -out=tf.plan` → read → `make apply`.

---

## Step 12 – End of every session: `make sleep`

```bash
make sleep
```
It shows a plan and asks `[y/N]`. Read the plan line: it should only **destroy** things (≈150) and change a few.
Type `y`. Hub VPC, logs, CloudTrail, budget and detection stay on, so the next session is one `make plan` +
`make apply` away (then `make vpn-setup` and confirm the WAF email again).

---

## Step 13 – When you are completely done: remove everything

```bash
make destroy           # type "yes" after reading the list
```
Then by hand:
1. **EC2 → Snapshots**: delete any snapshot tagged `Case=IR-001` (evidence from step 11).
2. **S3**: empty and delete `secnet-tfstate-<ACCOUNT_ID>`.
3. **IAM → Users → secnet-lab → Security credentials**: deactivate and delete the access key.
4. Next day: **Billing → Cost Explorer** should show nothing still costing money.

---

## Troubleshooting

| You see | Cause | Fix |
|---|---|---|
| `No valid credential sources found` / `ExpiredToken` | `AWS_PROFILE` not set in this terminal | `export AWS_PROFILE=secnet`, check with `aws sts get-caller-identity` |
| `chdir terraform/envs/dev: no such file or directory` | wrong folder | `cd` back to the `aws-secure-network` folder |
| `Error acquiring the state lock` | a previous command was interrupted | wait a minute; if it stays, ask Alber before using `force-unlock` |
| `VpcLimitExceeded` | VPC quota (step 5a) | wait for the quota increase, plan + apply again |
| `zsh: event not found` | a `!` inside double quotes in zsh | use single quotes around that value |
| A test fails right after `make apply` | some services need a few minutes (CloudFront, SSM agents, Config) | wait 5 minutes and run that test again: `make demo ARGS="--only T17"` |
| `make vpn-setup`: router not Online | the router is still booting | wait 3 minutes, run it again |
| No alarm emails | subscription not confirmed | click "Confirm subscription" in each AWS email |

**Security rules (always):** never commit `terraform.tfvars`, `*.plan` or state files; never share access keys,
the VPN key or downloaded VPN configs; blur public IPs and keys in screenshots.
