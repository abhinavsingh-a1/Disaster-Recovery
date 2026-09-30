# One aliased provider per region; every resource chooses its site explicitly.
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = local.common_tags
  }
}

# Route 53 health check metrics only exist in us-east-1, so the alarm that
# detects a primary-site outage (and triggers automated failover) lives here.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}
