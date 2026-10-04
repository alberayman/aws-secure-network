# Change log (system of record for applies and destroys)

Every `terraform apply`, `terraform destroy`, `make sleep` or hand-made change in the shared
AWS account gets one entry here, newest first (see `CHANGE_POLICY.md` in the project folder).

| Date / time (UTC) | Who applied | Tier | Change (switch / module) | Plan summary | Approved by | Team chat notice | Result / verification |
|---|---|---|---|---|---|---|---|
| 2026-10-04 ~13:10 | Alber (secnet-lab) | 1 | Terraform S3 backend connected (`terraform init`), provider pinned in `.terraform.lock.hcl` | n/a – no AWS resources created | Alber | n/a | `terraform validate`: valid |
| 2026-10-04 12:56 | Alber (secnet-lab) | 2 | S3 state bucket `secnet-tfstate-871925762150` created by hand (console): versioning, Block Public Access, SSE-S3, tags | n/a – not managed by Terraform | Alber | n/a | `get-bucket-versioning` = Enabled; all 4 public-access blocks true; evidence `w0-0.4-state-bucket-*.png` |
| 2026-10-04 12:48 | Alber (secnet-lab) | 1 | Service Quotas: VPCs per Region (eu-west-1) 5 → 10 requested | n/a | Alber | n/a | Status PENDING; re-check before Week 2 |
| 2026-10-04 12:19–12:25 | Alber (techguy) | 3 | IAM: group `secnet-lab-admins` (AdministratorAccess) + user `secnet-lab` (console + MFA + 1 access key, tagged) created for this project only | n/a – IAM managed by hand | Alber | n/a | `sts get-caller-identity` = user/secnet-lab; evidence `w0-0.1-*.png`, `w0-0.3-sts-identity.png`. Remove on clean-up day |
