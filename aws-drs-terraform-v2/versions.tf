terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }

  # Remote state (S3 + native lockfile). Configure with:
  #   terraform init -backend-config=backend.hcl
  # See bootstrap/ and backend.hcl.example.
  backend "s3" {}
}

# Primary (production) region
provider "aws" {
  region = var.primary_region
  default_tags {
    tags = local.common_tags
  }
}

# Disaster recovery region (same as primary in cross-az mode)
provider "aws" {
  alias  = "dr"
  region = local.dr_region
  default_tags {
    tags = local.common_tags
  }
}

# Route 53 health-check metrics only exist in us-east-1
provider "aws" {
  alias  = "global"
  region = "us-east-1"
  default_tags {
    tags = local.common_tags
  }
}
