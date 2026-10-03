terraform {
  required_version = "~> 1.11.4"

  # Keep the bucket's own state separate from the bucket it manages.
  backend "local" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.59.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Purpose   = "Terraform state"
    }
  }
}
