# Two provider aliases = two regions managed from one configuration.
# "primary" plays the role of us-east-1 (N. Virginia) in the talk,
# "dr" plays the role of us-east-2 (Ohio).

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
