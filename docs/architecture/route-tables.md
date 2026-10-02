# Route tables (Week 2, Member 1)

Fill from the console or `aws ec2 describe-route-tables` (Guide 2.1).

| Route table | Destination | Target | Why |
|---|---|---|---|
| secnet-public-rt | 0.0.0.0/0 | igw- | |
| secnet-private-rt | 0.0.0.0/0 | nat- | |
| secnet-private-rt | 10.1.0.0/16 | pcx- | |
| secnet-private-rt | 10.2.0.0/16 | tgw- | |
| secnet-private-rt | 192.168.0.0/16 | tgw- | |
| secnet-spoke-a-rt | 10.0.0.0/16 | pcx- | |
| secnet-spoke-b-rt | 10.0.0.0/16 | tgw- | |
| secnet-onprem-rt | 0.0.0.0/0 | igw- | |
| secnet-onprem-rt | 10.0.0.0/8 | eni- (strongSwan) | |
| TGW default | 10.0.0.0/16 | hub attachment (propagated) | |
| TGW default | 10.2.0.0/16 | spoke B attachment (propagated) | |
| TGW default | 192.168.0.0/16 | VPN attachment (static) | |

## Allow / deny matrix

| From \ To | Hub | Spoke A | Spoke B | Office | Internet |
|---|---|---|---|---|---|
| Hub | ✅ | ✅ peering | ✅ TGW | ✅ VPN | ✅ NAT |
| Spoke A | ✅ | – | ❌ not transitive | ❌ | ❌ |
| Spoke B | ✅ | ❌ | – | ❌ by design | ❌ |
| Office | ✅ | ❌ | ❌ by design | – | ✅ own IGW |
