# =========================================================
# TERRAFORM
# =========================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    tls = {
      source = "hashicorp/tls"
    }

    local = {
      source = "hashicorp/local"
    }
  }
}


# =========================================================
# AWS PROVIDER
# =========================================================

provider "aws" {
  region = var.aws_region
}


# =========================================================
# CURRENT AWS ACCOUNT
# =========================================================

data "aws_caller_identity" "current" {}
