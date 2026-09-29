data "aws_availability_zones" "primary" {
  state = "available"
}

data "aws_availability_zones" "dr" {
  provider = aws.dr
  state    = "available"
}

locals {
  name        = var.project_name
  dr_region   = var.dr_mode == "cross-region" ? var.dr_region : var.primary_region
  same_region = var.dr_mode == "cross-az"

  primary_azs = slice(data.aws_availability_zones.primary.names, 0, 2)
  # cross-az mode: recover into two *different* AZs of the same region
  dr_azs = local.same_region ? slice(data.aws_availability_zones.dr.names, 2, 4) : slice(data.aws_availability_zones.dr.names, 0, 2)

  source_instance_ids = [for k in sort(keys(module.protected_server)) : module.protected_server[k].instance_id]

  common_tags = merge({
    Project    = var.project_name
    ManagedBy  = "terraform"
    Repository = "aws-drs-terraform"
    DRMode     = var.dr_mode
  }, var.tags)
}
