terraform {
  required_version = "~> 1.11.4"

  # Populate from a local backend.hcl only after creating the state bucket.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.59.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.13.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.1.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
    }
  }
}
