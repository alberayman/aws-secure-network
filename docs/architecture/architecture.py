"""Architecture diagram for the README (diagram as code).

Regenerate:  pip install diagrams  (needs graphviz)  ->  python3 architecture.py
Output: architecture.png next to this file.
"""
from diagrams import Cluster, Diagram, Edge
from diagrams.aws.analytics import Athena
from diagrams.aws.compute import EC2
from diagrams.aws.database import RDS
from diagrams.aws.general import Client, Users, GenericOfficeBuilding
from diagrams.aws.integration import SNS
from diagrams.aws.management import Cloudtrail, Cloudwatch, SystemsManager
from diagrams.aws.network import (ALB, NLB, CloudFront, ClientVpn, Endpoint, InternetGateway,
                                  NATGateway, Privatelink, Route53HostedZone, SiteToSiteVpn,
                                  TransitGateway, VPCFlowLogs, VPCPeering)
from diagrams.aws.security import SecretsManager, WAF
from diagrams.aws.storage import S3

graph = {"fontsize": "22", "fontname": "Helvetica-Bold", "pad": "0.6", "nodesep": "0.55",
         "ranksep": "1.0", "splines": "spline", "labelloc": "t"}
node = {"fontsize": "12", "fontname": "Helvetica"}
edge = {"fontsize": "11", "fontname": "Helvetica"}

def vpc(label):
    return Cluster(label, graph_attr={"bgcolor": "#F2F9F2", "pencolor": "#248814", "fontsize": "14",
                                      "fontname": "Helvetica-Bold", "style": "rounded"})

def subnet(label, public):
    color = "#E6F2F8" if public else "#EEF0F8"
    pen = "#147EBA" if public else "#5A6BB0"
    return Cluster(label, graph_attr={"bgcolor": color, "pencolor": pen, "fontsize": "12",
                                      "fontname": "Helvetica", "style": "rounded,dashed"})

with Diagram("Secure AWS Network Architecture & Hybrid Connectivity  (DEPI ONL5_ISS11_G1)",
             filename="architecture", outformat="png", show=False, direction="LR",
             graph_attr=graph, node_attr=node, edge_attr=edge):

    users = Users("Internet users")
    remote = Client("Remote user")

    with Cluster("Edge (global, WAF in us-east-1)",
                 graph_attr={"bgcolor": "#FFF6EC", "pencolor": "#ED7100", "style": "rounded",
                             "fontsize": "14", "fontname": "Helvetica-Bold"}):
        waf = WAF("AWS WAF\nmanaged rules, rate, geo")
        cf = CloudFront("CloudFront\nHTTPS")

    with Cluster("AWS Cloud · eu-west-1",
                 graph_attr={"bgcolor": "#FFFFFF", "pencolor": "#232F3E", "style": "rounded",
                             "fontsize": "16", "fontname": "Helvetica-Bold"}):

        site = S3("Site bucket\n(private, OAC)")
        cvpn = ClientVpn("Client VPN\nmutual TLS")
        tgw = TransitGateway("Transit Gateway")

        with vpc("Hub VPC 10.0.0.0/16  (2 AZs)"):
            igw = InternetGateway("Internet gateway")
            with subnet("Public subnets 10.0.1.0/24 · 10.0.2.0/24", True):
                alb = ALB("ALB :80")
                nat = NATGateway("NAT gateway")
            with subnet("Private subnets 10.0.11.0/24 · 10.0.12.0/24  (NACL)", False):
                web = EC2("Web server\nIMDSv2, no SSH")
                db = RDS("RDS MySQL\nencrypted")
                ple = Privatelink("PrivateLink\nendpoint")
            peer = VPCPeering("VPC peering")

        with vpc("Spoke A 10.1.0.0/16"):
            spoke_a = EC2("Test host\nno internet")

        with vpc("Spoke B 10.2.0.0/16"):
            nlb = NLB("NLB\n(endpoint service)")
            spoke_b = EC2("Test host\nno internet")
            ssm_ep = Endpoint("SSM interface\nendpoints")

        with Cluster("Simulated office 192.168.0.0/16 (VPC)",
                     graph_attr={"bgcolor": "#F7F7F7", "pencolor": "#7D8998", "style": "rounded",
                                 "fontsize": "14", "fontname": "Helvetica-Bold"}):
            office = GenericOfficeBuilding("strongSwan\ncustomer gateway")

        vpn = SiteToSiteVpn("Site-to-Site VPN\nIPsec")

        with Cluster("Security, access & monitoring",
                     graph_attr={"bgcolor": "#FBEFF4", "pencolor": "#C7131F", "style": "rounded",
                                 "fontsize": "14", "fontname": "Helvetica-Bold"}):
            ssm = SystemsManager("Session Manager")
            secrets = SecretsManager("Secrets Manager\nRDS password")
            trail = Cloudtrail("CloudTrail")
            flow = VPCFlowLogs("VPC Flow Logs")
            logs = S3("Log bucket")
            athena = Athena("Athena\nIR queries")
            cw = Cloudwatch("CloudWatch alarms\nscan · SSH · WAF")
            sns = SNS("SNS → email")
            dns = Route53HostedZone("Route 53\nprivate zone + health check")

    # Static site path
    users >> Edge(label="HTTPS", color="#ED7100") >> cf
    waf - Edge(style="dotted", color="#ED7100") - cf
    cf >> Edge(label="OAC", color="#ED7100") >> site

    # App path (3 tiers)
    users >> Edge(label="HTTP", color="#147EBA") >> igw >> Edge(color="#147EBA") >> alb
    alb >> Edge(label=":80 from ALB SG", color="#147EBA") >> web
    web >> Edge(label=":3306 from web SG", color="#147EBA") >> db
    web >> Edge(label="outbound only", style="dashed", color="#7D8998") >> nat

    # Connectivity
    web - Edge(color="#248814") - peer - Edge(label="peering", color="#248814") - spoke_a
    web - Edge(color="#8C4FFF") - tgw - Edge(label="TGW", color="#8C4FFF") - spoke_b
    office - Edge(color="#8C4FFF") - vpn - Edge(label="IPsec", color="#8C4FFF") - tgw
    remote >> Edge(label="TLS", color="#8C4FFF") >> cvpn >> Edge(label="hub only", color="#8C4FFF") >> web
    web >> Edge(label="no routing", style="dashed", color="#248814") >> ple >> nlb >> spoke_b
    ssm_ep - Edge(style="dotted", color="#7D8998") - spoke_b

    # Security & monitoring
    ssm >> Edge(label="shell, no SSH", style="dashed", color="#C7131F") >> web
    flow >> Edge(color="#C7131F") >> logs >> Edge(color="#C7131F") >> athena
    trail >> Edge(color="#C7131F") >> logs
    flow >> Edge(color="#C7131F") >> cw >> Edge(color="#C7131F") >> sns
