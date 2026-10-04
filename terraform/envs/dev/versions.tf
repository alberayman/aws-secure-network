terraform {
  required_version = ">= 1.10" # S3 native state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  # Step 0.4 in Guide 0: create the state bucket by hand, then uncomment and run `terraform init`.
  backend "s3" {
    bucket       = "secnet-tfstate-871925762150"
    key          = "secure-network/dev.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "secure-network"
      Group     = "ONL5_ISS11_G1"
      ManagedBy = "terraform"
    }
  }
}

# CloudFront-scope WAF, its logs and its alarm must live in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project   = "secure-network"
      Group     = "ONL5_ISS11_G1"
      ManagedBy = "terraform"
    }
  }
}
