"""Traffic-flow diagram: what talks to what, through what, on which port.
Run: python3 traffic_flows.py && python3 render.py traffic-flows
"""
from svgkit import Svg, INK

WEB, SITE, PEER, TGW, PL, MGMT, OUT = "#147EBA", "#ED7100", "#7AA116", "#8C4FFF", "#00A4A6", "#DD344C", "#7D8998"
SOFT, RED = "#F7F5FC", "#D13212"

ROWS = [
    (SITE, "Public website", "static content at the edge",
     [("users", "Internet user"), ("cloudfront", "CloudFront\n+ AWS WAF"), ("simple-storage-service-s3", "Site bucket\nprivate")],
     ["HTTPS", "OAC only"], "WAF blocks SQLi, XSS, bad IPs; the bucket has no public access"),
    (WEB, "Web application", "3 network tiers, each only talks to the next",
     [("users", "Internet user"), ("cloudfront", "CloudFront\n+ AWS WAF"), ("elb-application-load-balancer", "ALB\npublic subnets"),
      ("ec2", "Web server"), ("rds", "RDS MySQL")],
     ["HTTPS", ":80 + secret header", ":80 from ALB SG", ":3306 from web SG"], "Same WAF as the site; the ALB refuses anyone but our CloudFront. Web and DB have no public IP"),
    (MGMT, "Admin access", "no SSH keys, no open ports",
     [("user", "Administrator"), ("systems-manager", "Session\nManager"), ("ec2", "Web server")],
     ["IAM + MFA", "<agent connects out :443"], "No inbound port at all: the agent dials out. Spokes reach SSM via interface endpoints; every session in CloudTrail"),
    (PEER, "Hub ↔ Spoke A", "VPC peering",
     [("ec2", "Web server\n10.0.11.x"), ("vpc-peering", "VPC peering"), ("ec2", "Spoke A host\n10.1.1.x")],
     ["route 10.1.0.0/16", "route 10.0.0.0/16"], "Not transitive: Spoke A can never reach Spoke B or the office"),
    (TGW, "Hub ↔ Spoke B", "Transit Gateway",
     [("ec2", "Web server\n10.0.11.x"), ("transit-gateway-attachment", "TGW attachment\n/28 subnets"),
      ("transit-gateway", "Transit\nGateway"), ("ec2", "Spoke B host\n10.2.1.x")],
     ["private NACL", "", "TGW route"], "Attachment in its own subnets, so the hub NACL filters TGW traffic (tested)"),
    (TGW, "Office ↔ Hub", "Site-to-Site VPN",
     [("generic-office-building", "Office router\nstrongSwan"), ("site-to-site-vpn", "Site-to-Site VPN\n2 tunnels · 1 configured"),
      ("transit-gateway", "Transit\nGateway"), ("ec2", "Web server")],
     ["IPsec", "VPN attachment", "TGW route"], "IPsec-encrypted (office simulated in a VPC); the office reaches the hub, not Spoke B"),
    (TGW, "Remote employee", "Client VPN · design only, not deployed",
     [("client", "Laptop"), ("client-vpn", "Client VPN\nmutual TLS"), ("ec2", "Hub only")],
     ["TLS certificate", "authorization rule"], "Security groups still apply on the VPN; connections logged"),
    (PL, "Private service", "PrivateLink: one port, no routing",
     [("ec2", "Web server"), ("privatelink", "Interface\nendpoint 10.0.x"), ("privatelink", "Endpoint service\napproval required"),
      ("elb-network-load-balancer", "Internal NLB"), ("ec2", "Spoke B host")],
     [":80", "AWS PrivateLink", "", ":80"], "Port 80 only (22 tested closed). Would also work with overlapping CIDRs (design property, not tested)"),
    (OUT, "Outbound updates", "private servers start every connection",
     [("ec2", "Web server"), ("nat-gateway", "NAT gateway"), ("internet-gateway", "Internet\ngateway")],
     ["0.0.0.0/0 route", ""], "Nothing on the internet can open a connection back in; S3 traffic skips NAT via the gateway endpoint"),
    (MGMT, "Detection", "alarms in minutes",
     [("vpc-flow-logs", "Flow Logs\nto CloudWatch Logs"), ("cloudwatch", "Metric filters\nrejects · SSH"),
      ("cloudwatch", "CloudWatch\nalarms"), ("simple-notification-service-sns", "SNS → email")],
     ["", "threshold", "alarm"], "Rejected-flow / SSH alarms (eu-west-1); the WAF-blocked alarm uses WAF's own metric (us-east-1)"),
    (MGMT, "Investigation", "everything is kept",
     [("cloudtrail", "CloudTrail multi-region\n+ Flow Logs every VPC"), ("simple-storage-service-s3", "Log bucket\nencrypted · versioned"), ("athena", "Athena")],
     ["delivered", "SQL"], "Who did what (CloudTrail) and who talked to whom (Flow Logs), queried after an alert"),
]

BLOCKED = [
    ("Internet → web server or database directly", "no public IP · security groups", True),
    ("Internet → port 22 anywhere", "no SSH rule in any security group (T7)", True),
    ("Spoke A ↔ Spoke B", "peering is not transitive · no route", True),
    ("Office → Spoke B", "separate TGW route tables", True),
    ("Spokes → internet", "no internet gateway, no NAT", True),
    ("Hub → Spoke B port 22 via PrivateLink", "only :80 is published", True),
    ("Internet → ALB directly (skip CloudFront)", "CloudFront prefix list + secret header", True),
]

ROW_H, TOP = 112, 150
H = TOP + len(ROWS) * ROW_H + 310
s = Svg(2000, H)
s.text(1000, 48, "Traffic flows: who talks to whom, through what, on which port", 28, INK, "middle", "700")
s.text(1000, 76, "Arrows point from the side that STARTS the connection · replies are allowed by stateful security groups and NACL ephemeral-port rules", 14, "#545B64", "middle")
s.text(40, 128, "FLOW", 12, "#545B64", weight="700")
s.text(440, 128, "PATH", 12, "#545B64", weight="700")
s.text(1560, 128, "WHY IT IS SECURE", 12, "#545B64", weight="700")

for i, (c, title, sub, nodes, labels, note) in enumerate(ROWS):
    y = TOP + i * ROW_H
    cy = y + 48
    if i % 2 == 0:
        s.box(20, y, 1960, ROW_H - 6, "", "#FFFFFF", SOFT, rx=8, sw=0)
    s.badge(52, cy, str(i + 1), c, r=17)
    s.text(84, cy - 4, title, 17, INK, weight="700")
    s.text(84, cy + 18, sub, 13, "#545B64")
    n = len(nodes)
    x0, x1 = 480, 1480
    step = (x1 - x0) / (n - 1)
    xs = [x0 + k * step for k in range(n)]
    for k in range(n - 1):
        lab = labels[k]
        if lab.startswith("<"):   # right-to-left hop: the node on the right starts the connection
            lab = lab[1:]
            s.line([(xs[k + 1] - 30, cy), (xs[k] + 34, cy)], c, sw=2.4)
        else:
            s.line([(xs[k] + 30, cy), (xs[k + 1] - 34, cy)], c, sw=2.4)
        if lab:
            s.pill((xs[k] + xs[k + 1]) / 2, cy - 1, lab, c)
    for (ic, lab), x in zip(nodes, xs):
        s.icon(ic, x, cy, lab, size=48, fs=12)
    # note, wrapped to two lines
    words, line, lines = note.split(), "", []
    for w in words:
        if len(line) + len(w) > 50:
            lines.append(line); line = w
        else:
            line = (line + " " + w).strip()
    lines.append(line)
    for k, l in enumerate(lines):
        s.text(1560, cy - 4 + k * 18, l, 13.5, INK)

# blocked paths
by = TOP + len(ROWS) * ROW_H + 20
s.box(20, by, 1960, 270, "", RED, "#FDF2F2", rx=10)
s.text(40, by + 32, "Blocked on purpose", 18, RED, weight="700")
s.text(1960, by + 32, "✓ tested in the Terraform build", 13, "#1D8102", "end", "600")
for k, (what, why, ok) in enumerate(BLOCKED):
    col, row = k % 3, k // 3
    x, yy = 50 + col * 650, by + 80 + row * 70
    s.cross(x + 12, yy - 5, RED, r=14)
    s.text(x + 40, yy - 6, what, 15, INK, weight="700")
    s.text(x + 40, yy + 15, why + ("  ✓" if ok else "  · VPN session"), 13, "#545B64")

open("traffic-flows.svg", "w").write(s.render())
print("ok", H)
