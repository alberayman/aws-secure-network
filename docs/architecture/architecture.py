"""Architecture diagram v2 (hand-laid SVG, AWS Architecture Icons + group colours).
Run: python3 architecture.py && python3 render.py architecture
"""
from svgkit import Svg, INK

REGION, VPC, SOFT = "#00A4A6", "#8C4FFF", "#F7F5FC"
PUB, PUBF, PRV, PRVF = "#7AA116", "#F2F6E8", "#00A4A6", "#E6F6F7"
SEC, GREY = "#DD344C", "#7D8998"
WEB, SITE, PEER, TGW, PL, MGMT, OUT = "#147EBA", "#ED7100", "#7AA116", "#8C4FFF", "#00A4A6", "#DD344C", "#7D8998"

s = Svg(2000, 1290)
s.text(1000, 42, "Secure AWS Network Architecture & Hybrid Connectivity", 28, INK, "middle", "700")
s.text(1000, 68, "DEPI ONL5_ISS11_G1  ·  eu-west-1  ·  built with Terraform", 14, "#545B64", "middle")

# ---------------- outside AWS ----------------
s.box(15, 95, 225, 230, "Edge · site + app", GREY, dash=True, size=13)
s.text(30, 135, "WAF scope: us-east-1", 11.5, "#545B64")
s.icon("waf", 75, 205, "AWS WAF\nrules · rate · geo")
s.text(30, 300, "WAF logs + alarm → SNS", 11, "#545B64")
s.text(30, 314, "(us-east-1, topic secnet-alerts)", 11, "#545B64")
s.icon("cloudfront", 180, 205, "CloudFront\nsite + app")
s.box(15, 355, 225, 900, "Outside AWS", GREY, dash=True, size=13)
s.icon("users", 127, 470, "Internet users")
s.icon("client", 127, 700, "Remote employee")
s.icon("user", 127, 1085, "Administrator\nIAM user + MFA")

# ---------------- AWS cloud / region ----------------
s.box(260, 95, 1725, 1180, "AWS Cloud", INK, size=16)
s.box(275, 130, 1695, 1130, "Region eu-west-1", REGION, dash=True, size=14)
s.icon("simple-storage-service-s3", 335, 230, "Site bucket\nprivate · OAC")
s.icon("client-vpn", 335, 700, "Client VPN\n(design only)")

# Hub VPC
s.box(400, 165, 690, 760, "Hub VPC  10.0.0.0/16  ·  2 AZs", VPC, SOFT)
s.icon("internet-gateway", 400, 470, "")
s.text(400, 520, "Internet", 12.5, INK, "middle", "600"); s.text(400, 535, "gateway", 12.5, INK, "middle", "600")
s.box(450, 200, 205, 560, "Public subnets", PUB, PUBF, size=13, bold=False)
s.text(464, 240, "10.0.1.0/24 · 10.0.2.0/24", 11.5, "#545B64")
s.icon("elb-application-load-balancer", 552, 380, "Application LB\nCloudFront only")
s.icon("nat-gateway", 552, 610, "NAT gateway\noutbound only")
s.icon("endpoint", 552, 840, "S3 gateway endpoint\nroute-table target")
s.icon("simple-storage-service-s3", 335, 880, "Amazon S3\nregional service")
s.box(690, 200, 380, 520, "Private subnets  ·  NACL", PRV, PRVF, size=13, bold=False)
s.text(704, 240, "10.0.11.0/24 · 10.0.12.0/24", 11.5, "#545B64")
s.icon("ec2", 780, 380, "Web server\nIMDSv2 · no SSH")
s.icon("rds", 975, 380, "RDS MySQL\nencrypted · private")
s.icon("privatelink", 975, 590, "PrivateLink\ninterface endpoint")
s.box(690, 745, 380, 160, "TGW attachment subnets", PRV, PRVF, size=13, bold=False)
s.text(704, 785, "10.0.254.0/28 · 10.0.254.16/28", 11.5, "#545B64")
s.icon("transit-gateway-attachment", 975, 830, "TGW attachment\nNACL applies")

# connectivity column
s.icon("vpc-peering", 1180, 250, "VPC peering\nnon-transitive")
s.icon("transit-gateway", 1180, 830, "Transit Gateway\nASN 64512")

# Spokes
s.box(1270, 165, 690, 205, "Spoke A  10.1.0.0/16  ·  no IGW / NAT", VPC, SOFT)
s.box(1290, 200, 650, 155, "Private subnet  10.1.1.0/24", PRV, PRVF, size=13, bold=False)
s.icon("ec2", 1420, 280, "Test host")
s.icon("endpoint", 1820, 280, "SSM endpoints ×3\nssm · ssmmessages · ec2messages")
s.box(1270, 420, 690, 270, "Spoke B  10.2.0.0/16  ·  no IGW / NAT", VPC, SOFT)
s.box(1290, 455, 650, 220, "Private subnet  10.2.1.0/24", PRV, PRVF, size=13, bold=False)
s.icon("privatelink", 1380, 575, "Endpoint service\nacceptance required")
s.icon("elb-network-load-balancer", 1545, 575, "Internal NLB\nwith SG")
s.icon("ec2", 1700, 575, "Test host\n:80 service")
s.icon("endpoint", 1860, 575, "SSM endpoints ×3")
s.box(1500, 740, 460, 185, "Simulated office  192.168.0.0/16", VPC, SOFT)
s.box(1520, 775, 420, 135, "Public subnet", PUB, PUBF, size=13, bold=False)
s.icon("generic-office-building", 1820, 845, "strongSwan\ncustomer gateway")
s.icon("site-to-site-vpn", 1400, 830, "Site-to-Site VPN\n2 tunnels · 1 configured")

# Security, access & monitoring (same background as the VPCs)
s.box(400, 975, 1560, 270, "", SEC, SOFT)
s.text(1945, 997, "Security, access & monitoring", 15, INK, "end", "700")
s.icon("systems-manager", 500, 1085, "Session Manager\nshell without SSH")
s.icon("secrets-manager", 660, 1085, "Secrets Manager\nDB password")
s.icon("route-53-hosted-zone", 820, 1085, "Route 53 private\nzone · health check")
s.icon("cloudtrail", 1010, 1045, "CloudTrail\nmulti-region")
s.icon("vpc-flow-logs", 1010, 1165, "VPC Flow Logs\nevery VPC")
s.icon("simple-storage-service-s3", 1290, 1045, "Log bucket\nencrypted · versioned")
s.icon("athena", 1530, 1045, "Athena\ninvestigation")
s.icon("cloudwatch", 1530, 1165, "CloudWatch alarms\neu-west-1 + us-east-1")
s.icon("simple-notification-service-sns", 1820, 1165, "SNS → email\n2 topics")

# ---------------- connections ----------------
# static site
s.line([(150, 440), (224, 360), (224, 222), (214, 222)], SITE, "HTTPS", (224, 320))
s.line([(105, 205), (148, 205)], SITE, arrow=False, dash="3 4")
s.line([(212, 192), (290, 192), (290, 215), (303, 215)], SITE, "OAC", (262, 160))
# web app: internet -> CloudFront + WAF -> IGW -> ALB (CloudFront IPs + secret header only) -> web -> RDS
s.line([(170, 445), (232, 380), (232, 236), (214, 236)], WEB)
s.line([(212, 206), (250, 206), (250, 470), (368, 470)], WEB, "HTTP + secret header", (322, 490))
s.line([(432, 470), (490, 470), (490, 380), (520, 380)], WEB)
s.line([(584, 380), (748, 380)], WEB, ":80 from ALB SG", (668, 366))
s.line([(812, 380), (943, 380)], WEB, ":3306", (878, 366))
s.line([(755, 456), (755, 520), (640, 590), (584, 600)], OUT, dash="6 5")
# private subnets reach S3 (OS packages, SSM agent updates) without NAT: route table -> gateway endpoint
s.line([(790, 456), (790, 700), (620, 700), (620, 840), (584, 840)], OUT, "S3 route", (620, 775), dash="6 5")
s.line([(520, 850), (470, 850), (470, 880), (367, 880)], OUT, dash="6 5")
# remote employee -> client VPN -> hub only
s.line([(160, 700), (303, 700)], TGW, "TLS", (232, 690), dash="6 5")
s.line([(367, 700), (430, 700), (430, 945), (700, 945), (700, 395), (746, 395)], TGW, "hub only", (478, 945), dash="6 5")
# peering web <-> Spoke A
s.line([(780, 348), (780, 300), (1120, 300), (1150, 262)], PEER, both=True)
s.line([(1212, 250), (1240, 250), (1240, 280), (1388, 280)], PEER, "peering", (1300, 280), both=True)
# TGW path: web -> attachment -> TGW -> Spoke B
s.line([(820, 456), (820, 720), (905, 720), (905, 830), (943, 830)], TGW, both=True)
s.line([(1007, 830), (1148, 830)], TGW, both=True)
s.line([(1180, 798), (1180, 715), (1720, 715), (1720, 652)], TGW, "TGW route", (1440, 715), both=True)
s.line([(1212, 845), (1368, 845)], TGW, both=True)
s.line([(1432, 845), (1788, 845)], TGW, "IPsec", (1640, 845), both=True)
# PrivateLink: one service, one port
s.line([(812, 395), (900, 430), (900, 590), (943, 590)], PL, ":80 only", (900, 505))
s.line([(1007, 590), (1100, 590), (1100, 560), (1348, 560)], PL, "PrivateLink", (1230, 560))
s.line([(1412, 575), (1513, 575)], PL)
s.line([(1577, 575), (1668, 575)], PL)
# SSM endpoints (dotted)
s.line([(1788, 280), (1452, 280)], MGMT, dash="2 4", arrow=False)
s.line([(1828, 575), (1732, 575)], MGMT, dash="2 4", arrow=False)
# admin -> Session Manager -> web
s.line([(160, 1085), (468, 1085)], MGMT, "IAM + MFA", (320, 1075))
s.line([(500, 1053), (500, 962), (672, 962), (672, 420), (746, 420)], MGMT, "shell, no SSH", (610, 962), dash="7 5")
# logging pipeline
s.line([(1042, 1045), (1258, 1045)], MGMT)
s.line([(1042, 1155), (1150, 1155), (1150, 1060), (1258, 1060)], MGMT)
s.line([(1322, 1045), (1498, 1045)], MGMT, "SQL", (1410, 1045))
s.line([(1042, 1175), (1498, 1175)], MGMT, "metric filters", (1300, 1175))
s.line([(1562, 1165), (1788, 1165)], MGMT, "alarm", (1680, 1165))

# legend
lx, ly = 1500, 72
items = [("Web app (CloudFront → ALB)", WEB, None), ("Static site", SITE, None), ("Peering", PEER, None), ("TGW / VPN", TGW, None),
         ("PrivateLink", PL, None), ("Management & logs", MGMT, None),
         ("Outbound only", OUT, "6 5"), ("Design only (not deployed)", TGW, "6 5"), ("Endpoint link", MGMT, "2 4")]
x = 1960 - sum(34 + len(t) * 6.6 + 22 for t, _, _ in items)   # right-aligned, width per label
for t, c, d in items:
    s.line([(x, 112), (x + 28, 112)], c, arrow=False, sw=3, dash=d)
    s.text(x + 34, 116, t, 11.5, INK)
    x += 34 + len(t) * 6.6 + 22

open("architecture.svg", "w").write(s.render())
print("ok")
