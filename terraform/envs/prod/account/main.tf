provider "aws" {
  region = "ap-northeast-1"
}

terraform {
  backend "s3" {
    region  = "ap-northeast-1"
    bucket  = "rpf-terraform-state-dev"
    key     = "rpf-301-prod.tfstate"
    encrypt = true
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "now" {}
locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.now.name
  stage      = "prod"
}

module "rpf_account" {
  source = "../../../modules/rpf_account"
  stage  = local.stage
}
