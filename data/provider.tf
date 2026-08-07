terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }

    tls = {
      source = "hashicorp/tls"
    }

    local = {
      source = "hashicorp/local"
    }
  }
}


provider "aws" {

  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_region


  endpoints {
    ec2 = "http://localstack-main:4566"
    sts = "http://localstack-main:4566"
    iam = "http://localstack-main:4566"
  }


  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}