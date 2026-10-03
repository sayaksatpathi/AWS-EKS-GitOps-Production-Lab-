terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Uncomment and configure for remote state:
  # backend "s3" {
  #   bucket         = "cloudlaunch-terraform-state"
  #   key            = "dev/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "cloudlaunch-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = "cloudlaunch"
      ManagedBy  = "terraform"
      Repository = "https://github.com/sayaksatpathi/AWS-EKS-GitOps-Production-Lab-"
    }
  }
}
