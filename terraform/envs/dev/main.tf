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
}

# ---------------- Week 1: EC2 + ALB + RDS (Members 2 and 4) ----------------
module "compute" {
  source             = "../../modules/compute"
  name               = var.name
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
}

# ---------------- Week 2: spokes, peering, TGW, VPN (Member 3) ----------------
module "connectivity" {
  count                      = local.hybrid ? 1 : 0
  source                     = "../../modules/connectivity"
  name                       = var.name
  az                         = local.azs[0]
  hub_vpc_id                 = module.vpc.vpc_id
  hub_vpc_cidr               = local.hub_cidr
  hub_private_subnet_ids     = module.vpc.private_subnet_ids
  hub_private_route_table_id = module.vpc.private_route_table_id
  instance_profile_name      = module.compute.ec2_profile_name
  spokes                     = local.spoke_cidrs
  onprem_cidr                = local.onprem_cidr
  enable_vpn                 = var.enable_vpn
}

# ---------------- Weeks 1, 2, 4: logging and detection (Member 5) ----------------
module "monitoring" {
  source = "../../modules/monitoring"
  name   = var.name
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
  count             = var.enable_edge ? 1 : 0
  source            = "../../modules/edge"
  name              = var.name
  blocked_countries = var.waf_blocked_countries
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
