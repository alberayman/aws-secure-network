data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
  hub_cidr    = "10.0.0.0/16"
  spoke_cidrs = { a = "10.1.0.0/16", b = "10.2.0.0/16" }
  onprem_cidr = "192.168.0.0/16"
  hybrid      = var.enable_hybrid
}

# ---------------- Week 1: hub VPC (Member 1) ----------------
module "vpc" {
  source               = "../../modules/vpc"
  name                 = var.name
  vpc_cidr             = local.hub_cidr
  azs                  = local.azs
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  enable_nat           = var.enable_nat
  extra_allowed_cidrs  = local.hybrid ? concat(values(local.spoke_cidrs), [local.onprem_cidr]) : []
  tgw_subnet_cidrs     = local.hybrid ? ["10.0.254.0/28", "10.0.254.16/28"] : []
  data_subnet_cidrs    = ["10.0.21.0/24", "10.0.22.0/24"] # D9
}

# ---------------- Week 1: EC2 + ALB + RDS (Members 2 and 4) ----------------
module "compute" {
  count              = var.enable_compute ? 1 : 0
  source             = "../../modules/compute"
  name               = var.name
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  db_subnet_ids      = module.vpc.data_subnet_ids # D9
  # Week 3: CloudFront + WAF in front of the ALB; the ALB accepts nothing else
  cloudfront_only           = var.enable_edge
  cloudfront_prefix_list_id = data.aws_ec2_managed_prefix_list.cloudfront.id
  origin_verify_secret      = var.enable_edge ? random_password.origin_verify[0].result : null
}

# AWS-managed list of CloudFront's origin-facing IP ranges
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# Shared secret between CloudFront and the ALB (stored only in the encrypted state)
resource "random_password" "origin_verify" {
  count   = var.enable_edge ? 1 : 0
  length  = 32
  special = false
}

# ---------------- Week 2: spokes, peering, TGW, VPN (Member 3) ----------------
module "connectivity" {
  count                      = local.hybrid ? 1 : 0
  source                     = "../../modules/connectivity"
  name                       = var.name
  az                         = local.azs[0]
  hub_vpc_id                 = module.vpc.vpc_id
  hub_vpc_cidr               = local.hub_cidr
  hub_tgw_subnet_ids         = module.vpc.tgw_subnet_ids
  hub_private_route_table_id = module.vpc.private_route_table_id
  instance_profile_name      = one(module.compute[*].ec2_profile_name)
  spokes                     = local.spoke_cidrs
  onprem_cidr                = local.onprem_cidr
  enable_vpn                 = var.enable_vpn
}

# ---------------- Weeks 1, 2, 4: logging and detection (Member 5) ----------------
module "monitoring" {
  source                 = "../../modules/monitoring"
  name                   = var.name
  alert_email            = var.alert_email
  reject_alarm_threshold = var.reject_alarm_threshold
  # 1-minute copy in CloudWatch for alarms (Week 4). Spoke A is where the drill's scan is REJECTed.
  cloudwatch_flowlog_vpc_ids = merge(
    { hub = module.vpc.vpc_id },
    local.hybrid ? { spoke_a = module.connectivity[0].spoke_vpc_ids["a"] } : {}
  )
  vpc_ids = merge(
    { hub = module.vpc.vpc_id },
    local.hybrid ? {
      spoke_a = module.connectivity[0].spoke_vpc_ids["a"]
      spoke_b = module.connectivity[0].spoke_vpc_ids["b"]
    } : {},
    local.hybrid && var.enable_vpn ? { onprem = module.connectivity[0].onprem_vpc_id } : {}
  )
}

# ---------------- Week 3: CloudFront + S3 + WAF (Member 4) ----------------
module "edge" {
  count                = var.enable_edge ? 1 : 0
  source               = "../../modules/edge"
  name                 = var.name
  blocked_countries    = var.waf_blocked_countries
  enable_app           = var.enable_compute
  alb_dns_name         = one(module.compute[*].alb_dns_name)
  origin_verify_secret = random_password.origin_verify[0].result
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
