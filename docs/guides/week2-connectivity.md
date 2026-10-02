# Week 2: Advanced connectivity and hybrid networking (step by step)

**Goal:** a hub-and-spoke network. Spoke A joins by VPC peering, Spoke B by Transit Gateway, and a simulated office joins by Site-to-Site VPN. The spokes have no internet and are managed through VPC endpoints, and Spoke B shares one service through PrivateLink.
**Gate to pass:** at least one VPN tunnel is **UP**, and the test matrix is filled in, including the failures we expect.

```
              Spoke A 10.1.0.0/16 ── peering ──┐
                                                Hub VPC 10.0.0.0/16 ── TGW ── Spoke B 10.2.0.0/16
   Office 192.168.0.0/16 (strongSwan) ═ IPsec VPN ═╝ (VPN attaches to the TGW)
```

Peering is **not transitive**: Spoke A can never reach Spoke B or the office through the hub. We test that and document it.

| Task | Member | Terraform files | Switch |
|---|---|---|---|
| 2.1 NACL, route docs, segmentation matrix | 1 | `modules/vpc` (`extra_allowed_cidrs`) | `enable_hybrid` |
| 2.2 Spokes, peering, TGW, VPN | 3 | `modules/connectivity/*` | `enable_hybrid`, `enable_vpn` |
| 2.3 VPC endpoints, PrivateLink | 4 | `envs/dev/endpoints.tf`, `privatelink.tf` | `enable_hybrid` |
| 2.4 Test instances + test report | 2 | `envs/dev/spoke_tests.tf` | `enable_hybrid` |
| 2.5 Flow Logs baseline | 5 | `modules/monitoring/flowlogs.tf` | automatic |
| 2.6 Reviews, cost, docs | 6 | `Makefile`, `scripts/` | - |

**Order:** first do everything in the console on Monday and Tuesday, then delete it. On Wednesday, set `enable_hybrid = true` and apply. On Thursday, set `enable_vpn = true`, apply, and configure strongSwan. The VPN takes the longest, so start it early.

---

## 2.1 Member 1: NACL, route documentation, segmentation

### Console steps
1. The Week 1 private NACL only trusts `10.0.0.0/16`. **VPC** > **Network ACLs** > `secnet-private-nacl` > **Inbound rules** > Edit: add 200 *All traffic* `10.1.0.0/16`, 201 `10.2.0.0/16`, 202 `192.168.0.0/16`, all Allow.
2. When 2.2 is done, record every route table in `docs/architecture/route-tables.md`:

| Route table | Destination | Target | Why |
|---|---|---|---|
| secnet-private-rt | 0.0.0.0/0 | nat-… | internet for private hosts |
| secnet-private-rt | 10.1.0.0/16 | pcx-… | peering to Spoke A |
| secnet-private-rt | 10.2.0.0/16 | tgw-… | Spoke B through the TGW |
| secnet-private-rt | 192.168.0.0/16 | tgw-… | office through the VPN |
| secnet-spoke-a-rt | 10.0.0.0/16 | pcx-… | back to the hub only |
| secnet-spoke-b-rt | 10.0.0.0/16 | tgw-… | back to the hub only |
| TGW default route table | 10.0.0.0/16, 10.2.0.0/16 | VPC attachments (propagated) | learned automatically |
| TGW default route table | 192.168.0.0/16 | VPN attachment (static) | added by us |

3. Draw the hub-and-spoke diagram (`docs/architecture/week2-hub-spoke.png`).
4. Write the **allow/deny matrix** (rows = from, columns = to) with the *expected* result; 2.4 fills in the *actual* result.

### Terraform
`modules/vpc/main.tf` → `dynamic "ingress"` loops over `extra_allowed_cidrs` (rule numbers 200, 201, 202). `envs/dev/main.tf` passes the three networks **only when** `enable_hybrid = true`.

Export routes for the document:
```bash
aws ec2 describe-route-tables --filters Name=tag:Project,Values=secure-network \
  --query "RouteTables[].{Name:Tags[?Key=='Name']|[0].Value,Routes:Routes[].[DestinationCidrBlock,GatewayId,NatGatewayId,TransitGatewayId,VpcPeeringConnectionId]}" --output json
aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id <tgw-rtb-id> --filters Name=state,Values=active
```

---

## 2.2 Member 3: spokes, peering, Transit Gateway, Site-to-Site VPN

### Part A: spoke and office VPCs (console)
1. **VPC** > **Create VPC** > **VPC only**, three times: `secnet-spoke-a` `10.1.0.0/16`, `secnet-spoke-b` `10.2.0.0/16`, `secnet-onprem` `192.168.0.0/16`. Each: *Actions > Edit VPC settings* > DNS resolution ✔ and DNS hostnames ✔.
2. **Subnets** > Create one subnet per VPC, all in the **same AZ as hub private subnet 1** (eu-west-1a): `10.1.1.0/24`, `10.2.1.0/24`, `192.168.1.0/24`.
3. A route table per VPC, associated with its subnet (`secnet-spoke-a-rt`, `secnet-spoke-b-rt`, `secnet-onprem-rt`).
4. Office only: **Internet gateways** > Create `secnet-onprem-igw` > attach to `secnet-onprem`; in `secnet-onprem-rt` add `0.0.0.0/0` → that IGW. The spokes get **no** IGW and **no** NAT, which is cheaper and safer.

### Part B: VPC peering, hub ↔ Spoke A
1. **Peering connections** > Create: requester `secnet-vpc`, accepter `secnet-spoke-a` (my account, this region). Then **Actions** > **Accept request**.
2. Routes on **both** sides: `secnet-private-rt` `10.1.0.0/16` → `pcx-…`; `secnet-spoke-a-rt` `10.0.0.0/16` → `pcx-…`.

### Part C: Transit Gateway, hub ↔ Spoke B
1. **Transit gateways** > Create `secnet-tgw`: ASN 64512, DNS support ✔, VPN ECMP ✔, default route table association ✔ and propagation ✔.
2. **Transit gateway attachments** > Create, type VPC: `secnet-vpc` (both **private** subnets) and `secnet-spoke-b` (its subnet). Wait for **Available**.
3. Routes: `secnet-private-rt` `10.2.0.0/16` → `tgw-…`; `secnet-spoke-b-rt` `10.0.0.0/16` → `tgw-…`.

### Part D: Site-to-Site VPN, office ↔ TGW (the hardest step: start early)
1. **EC2** > **Launch instance** `secnet-strongswan`: **Ubuntu 22.04**, `t3.micro`, no key pair, VPC `secnet-onprem`, its subnet, **Auto-assign public IP: Enable**, new SG `secnet-strongswan-sg` with inbound UDP 500, UDP 4500, *Custom protocol* 50 (ESP) from `0.0.0.0/0` (lab only) and All ICMP from `10.0.0.0/8`. IAM profile `secnet-ec2-profile`. Metadata V2 only.
2. After launch: **Actions** > **Networking** > **Change source/destination check** > **Stop** (it routes for others).
3. **Elastic IPs** > Allocate > **Associate** with the instance. Write the address down.
4. **Customer gateways** > Create `secnet-cgw`: IP = the Elastic IP, BGP ASN 65000.
5. **Site-to-Site VPN connections** > Create `secnet-vpn`: target **Transit gateway** `secnet-tgw`, customer gateway `secnet-cgw`, routing **Static**, *Local IPv4 network CIDR* `192.168.0.0/16`, *Remote IPv4 network CIDR* `10.0.0.0/8`. Create (≈5 minutes until *Available*).
6. **Transit gateway route tables** > the default table > **Routes** > **Create static route** `192.168.0.0/16` → the VPN attachment.
7. `secnet-private-rt`: `192.168.0.0/16` → `tgw-…`. `secnet-onprem-rt`: `10.0.0.0/8` → the strongSwan **network interface**.
8. Select the VPN > **Download configuration** > vendor *Strongswan*, platform *Ubuntu*, IKE version *ikev1*. The file holds the tunnel outside IPs and pre-shared keys. **It is secret: never commit it.**
9. Session Manager into the strongSwan instance:
```bash
sudo apt-get update && sudo apt-get install -y strongswan strongswan-starter
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
sudo tee /etc/ipsec.conf >/dev/null <<'EOF'
config setup
  charondebug="ike 1, knl 1, cfg 0"
conn %default
  keyexchange=ikev1
  ike=aes128-sha1-modp1024!
  esp=aes128-sha1-modp1024!
  ikelifetime=8h
  lifetime=1h
  dpddelay=10s
  dpdtimeout=30s
  dpdaction=restart
  authby=secret
  auto=start
  type=tunnel
  left=%defaultroute
  leftsubnet=192.168.0.0/16
  rightsubnet=10.0.0.0/8
conn tunnel1
  leftid=<ELASTIC_IP>
  right=<TUNNEL1_OUTSIDE_IP>
EOF
echo '<ELASTIC_IP> <TUNNEL1_OUTSIDE_IP> : PSK "<TUNNEL1_PSK>"' | sudo tee /etc/ipsec.secrets
sudo chmod 600 /etc/ipsec.secrets
sudo ipsec restart && sleep 10 && sudo ipsec statusall
```
Replace the three `<…>` values with the ones in the downloaded file (Tunnel 1). If anything differs from the file, **the file wins**.

**If the tunnel stays DOWN, check:**
- [ ] Source/dest check is stopped.
- [ ] The SG allows UDP 500 and 4500 and ESP.
- [ ] The Elastic IP equals the customer gateway IP.
- [ ] The PSK was copied exactly.
- [ ] `ike`/`esp` match the file.
- [ ] Look at `sudo journalctl -u strongswan-starter -n 50`.

One tunnel UP is enough for the lab. Two DOWN tunnels are normal before the instance is configured.

10. **Client VPN** and **Direct Connect**: designed, not built. Write `docs/week2/client-vpn-and-dx.md`, one section each. Cover what it is, when you would choose it, what it needs, the rough cost, and why we did not build it. Client VPN needs certificates in ACM and is billed per endpoint and per connection hour. Direct Connect needs a physical circuit from a partner.

**Delete before Terraform**, in this order:
1. The VPN connection and the customer gateway
2. The TGW attachments, then the TGW
3. The peering connection
4. The instance, then release the Elastic IP
5. The three VPCs

### Terraform (`terraform/modules/connectivity/`)
| File | Blocks | Console part |
|---|---|---|
| `spokes.tf` | `aws_vpc.spoke` / `aws_subnet.spoke` / `aws_route_table.spoke` with `for_each = var.spokes` (a, b) | A |
| `peering.tf` | `aws_vpc_peering_connection.hub_a` (`auto_accept`), routes both ways | B |
| `tgw.tf` | `aws_ec2_transit_gateway.this`, two VPC attachments, routes hub ↔ B and hub → office | C |
| `vpn.tf` | office VPC, IGW, router SG, `aws_instance.strongswan` (**`associate_public_ip_address = true`** so `apt` works at boot, `source_dest_check = false`), EIP, customer gateway, `aws_vpn_connection.this` (static, traffic selectors), TGW static route. Every block has `count = var.enable_vpn ? 1 : 0` | D |
| `outputs.tf` | `tgw_id`, `vpn_connection_id`, `strongswan_public_ip`, `vpn_tunnel1_address`, `vpn_tunnel1_psk` (**sensitive**) | |

Apply in two steps so the VPN problems do not block everyone else:
```bash
# terraform.tfvars: enable_hybrid = true
terraform plan -out w2a.tfplan && terraform apply w2a.tfplan
# when peering/TGW tests pass: enable_vpn = true
terraform plan -out w2b.tfplan && terraform apply w2b.tfplan
terraform output vpn_connection_id      # then step 8 in the console: Download configuration
```
Terraform builds the tunnels, but configuring strongSwan (step 9) is still done by hand. The tunnel PSK is in the Terraform state, which is one reason the state bucket must stay private.

### Check it worked
- Peering **Active**, TGW attachments **Available**, VPN **Tunnel details** shows *UP* (screenshot).
- `sudo ipsec statusall` shows `ESTABLISHED` and `INSTALLED`.
- From strongSwan: `ping -c 3 <web_private_ip>` works.

### Clean up
The TGW (≈$0.15/h for 3 attachments) and the VPN (≈$0.05/h) are the most expensive things we run. At the end of the day, run `make sleep`, which sets `enable_hybrid` and `enable_vpn` to false. The next day, apply again and redo step 9; the PSK and outside IPs will have changed.

---

## 2.3 Member 4: VPC endpoints and PrivateLink

The spokes have no internet, so their instances can only reach Systems Manager through **interface endpoints**.

### Console steps
**A. Endpoint security groups:** in **each** spoke VPC create `secnet-endpoint-sg-a` / `-b` with inbound HTTPS 443 from that spoke's CIDR.

**B. Three SSM endpoints per spoke:** **VPC** > **Endpoints** > Create > *AWS services*. Pick `com.amazonaws.eu-west-1.ssm`, the spoke VPC and its subnet, the endpoint SG, and tick **Enable DNS name**. Repeat for `ssmmessages` and `ec2messages`. That makes 6 endpoints in total (≈$0.01/h each).

**C. S3 gateway endpoint in the hub (free):** service `com.amazonaws.eu-west-1.s3`, type **Gateway**, VPC `secnet-vpc`, route table `secnet-private-rt`. Now S3 traffic from private hosts skips the NAT.

**D. PrivateLink: Spoke B publishes a service, the hub consumes it**
1. **Load balancers** > Create **Network Load Balancer** `secnet-spoke-b-nlb`: *Internal*, VPC `secnet-spoke-b`, its subnet, listener TCP 80 → new target group (instances, TCP 80) with `secnet-spoke-b-test` (2.4).
2. **Endpoint services** > Create: pick the NLB, **untick Acceptance required** (lab).
3. **Endpoints** > Create > *Endpoint services that use NLBs and GWLBs* > paste the service name > Verify. VPC `secnet-vpc`, both private subnets, SG `secnet-privatelink-consumer` (inbound TCP 80 from `10.0.0.0/16`).
4. From the hub web server: `curl http://<endpoint-DNS-name>` shows *Spoke B service*.

PrivateLink works **without any route** between the VPCs, and the consumer can only reach that one port. That is why it is the safest way to share a service.

### Terraform
- `envs/dev/endpoints.tf`: `setproduct(spokes, ["ssm","ssmmessages","ec2messages"])` builds the 6 endpoint keys (`a-ssm`, `a-ssmmessages`, …). The service name uses `data.aws_region.current`, so nothing is hard-coded.
- `envs/dev/privatelink.tf`: NLB → target group → listener → `aws_vpc_endpoint_service` → consumer `aws_vpc_endpoint` in the hub.
- Output `privatelink_dns` prints the name to curl.

### Check it worked
- **Systems Manager** > **Fleet Manager** lists both spoke instances, and Session Manager opens on them with no internet route.
- `curl http://$(terraform output -raw privatelink_dns)` from the hub web server returns the Spoke B page (screenshot).

---

## 2.4 Member 2: test instances and the hybrid connectivity test report

### Console steps
1. In each spoke launch Amazon Linux 2023 `t3.micro`: no public IP, profile `secnet-ec2-profile`, IMDSv2, SG `secnet-test-sg-a`/`-b` with ICMP + HTTP 80 from `10.0.0.0/8` and `192.168.0.0/16`. User data (no internet needed, Python is preinstalled):
```bash
#!/bin/bash
mkdir -p /srv/web && cd /srv/web
echo "Spoke B service" > index.html
nohup python3 -m http.server 80 >/dev/null 2>&1 &
```
2. When the endpoints from 2.3 exist, open Session Manager on each one.
3. Run the matrix and fill in `docs/week2/test-report.md`:

| # | From | To | Command | Expected | Why |
|---|---|---|---|---|---|
| 1 | Hub web | Spoke A test | `ping -c 3 10.1.1.x` | ✅ works | peering + both routes |
| 2 | Hub web | Spoke B test | `ping -c 3 10.2.1.x`; `curl http://10.2.1.x` | ✅ works | TGW |
| 3 | Spoke A | Spoke B | `ping -c 3 10.2.1.x` | ❌ fails | peering is not transitive and Spoke A has no route |
| 4 | Office router | Hub web | `ping -c 3 10.0.11.x` | ✅ works | VPN → TGW → hub |
| 5 | Office router | Spoke B | `ping -c 3 10.2.1.x` | ❌ fails | Spoke B's route table only knows the hub (segmentation) |
| 6 | Spoke A | Internet | `curl -m 5 https://example.com` | ❌ fails | no IGW, no NAT |
| 7 | Hub web | PrivateLink | `curl http://<privatelink_dns>` | ✅ works | endpoint, no routing |

4. Write the **test report**: purpose, setup, the table with *actual* results, an explanation of every failure (expected or not), and screenshots.

Test 5 is a design decision. If the team wants the office to reach Spoke B, add `192.168.0.0/16 → tgw` to Spoke B's route table, then re-test and document the change.

### Terraform (`envs/dev/spoke_tests.tf`)
- One SG per spoke and its rules. `setproduct(spokes, cidrs)` builds the ICMP and HTTP rules.
- `aws_instance.spoke` (for each a, b) with the same user data. Output `spoke_test_ips` prints the IPs for the matrix.
- The hub web server already allows ICMP from `10.0.0.0/8` and `192.168.0.0/16` (`modules/compute/security_groups.tf`).

---

## 2.5 Member 5: Flow Logs baseline

### Console steps
1. **VPC** > **Your VPCs** > select the hub > **Flow logs** tab > **Create flow log**. Set filter **All**, max aggregation interval **10 minutes**, destination **S3**, ARN `arn:aws:s3:::secnet-logs-<ACCOUNT_ID>/flowlogs/hub/`, and the **AWS default format**.
2. Repeat for spoke-a, spoke-b and onprem (`…/flowlogs/spoke_a/`, etc.).
3. 15 minutes after 2.4's tests, open S3 at `flowlogs/hub/AWSLogs/<account>/vpcflowlogs/eu-west-1/<date>/`, download one `.log.gz` and read it. The fields are `version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes start end action log-status`.
4. Write the baseline in `docs/week2/flowlogs-baseline.md`: top talkers, normal ports (80, 443, 3306, 123 and ICMP), and ports that should never appear (22, 3389).

### Terraform
`modules/monitoring/flowlogs.tf` creates one `aws_flow_log` per entry in `vpc_ids`. `envs/dev/main.tf` adds the spokes and the office automatically when their switches are on. The bucket policy already allows `delivery.logs.amazonaws.com`, so nothing else is needed.

### Check it worked
The flow log status is **Active** on every VPC, the `.log.gz` files arrive, and you can name the top 3 talkers.

---

## 2.6 Member 6: reviews, cost, documentation

1. Review every Week 2 pull request. Read each `.tf` file and check that:
   - nothing hard-codes an account ID, region or email;
   - every resource has a `Name` tag;
   - the plan is pasted in the pull request;
   - CI is green.
2. Write the cost note in `docs/week2/README.md`: hours with `enable_hybrid`/`enable_vpn` on × the rates in Guide 0.6. Add a **Billing** > **Cost Explorer** screenshot (group by Service, last 7 days).
3. Make sure `make sleep` works, and run it at the end of every session.
4. Fill `docs/week2/README.md` with all five deliverables linked: hub-and-spoke/TGW diagram, peering + endpoint setup, VPN configuration (**no secrets**), route table documentation, test report.
