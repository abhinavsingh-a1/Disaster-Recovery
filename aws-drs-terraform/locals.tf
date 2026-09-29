data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  name = var.project_name

  common_tags = merge(
    {
      Project   = var.project_name
      ManagedBy = "terraform"
      Scenario  = "aws-drs-cross-az-recovery"
    },
    var.extra_tags,
  )

  # One subnet per role, each in its own AZ (mirrors the video:
  # source = AZ a, staging = AZ b, recovery = AZ f).
  subnets = {
    source = {
      cidr      = cidrsubnet(var.vpc_cidr, 8, 1)
      az        = "${var.region}${var.source_az_suffix}"
      public_ip = true
    }
    staging = {
      cidr      = cidrsubnet(var.vpc_cidr, 8, 2)
      az        = "${var.region}${var.staging_az_suffix}"
      public_ip = false # DRS assigns public IPs to replication servers itself (create_public_ip)
    }
    recovery = {
      cidr      = cidrsubnet(var.vpc_cidr, 8, 3)
      az        = "${var.region}${var.recovery_az_suffix}"
      public_ip = true
    }
  }

  # Tag DRS puts on everything it creates in the staging area
  # (replication servers, staging volumes, snapshots). Used by scripts/cleanup-drs.sh.
  staging_area_tags = {
    DrsStagingArea = var.project_name
  }

  policy_arn_prefix = "arn:${data.aws_partition.current.partition}:iam::aws:policy"
}
