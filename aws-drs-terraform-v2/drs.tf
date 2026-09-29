# Forward replication: production -> DR staging area (private IP over peering)
module "drs_dr" {
  source    = "./modules/drs-replication"
  providers = { aws = aws.dr }

  name                             = "${local.name}-dr"
  vpc_id                           = module.network_dr.vpc_id
  staging_subnet_id                = module.network_dr.staging_subnet_id
  allowed_replication_cidrs        = [var.primary_vpc_cidr]
  replication_server_instance_type = var.replication_server_instance_type
  kms_key_arn                      = module.kms_dr.key_arn
  snapshot_retention_days          = var.snapshot_retention_days
  bandwidth_throttling_mbps        = var.bandwidth_throttling_mbps
  initialize_service               = var.initialize_drs_service
  use_private_ip                   = true
}

# Failback replication: recovery instances -> primary staging area.
# Not needed in cross-az mode (same Region = same DRS template).
module "drs_primary" {
  source = "./modules/drs-replication"
  count  = local.same_region ? 0 : 1

  name                             = "${local.name}-failback"
  vpc_id                           = module.network_primary.vpc_id
  staging_subnet_id                = module.network_primary.staging_subnet_id
  allowed_replication_cidrs        = [var.dr_vpc_cidr]
  replication_server_instance_type = var.replication_server_instance_type
  kms_key_arn                      = module.kms_primary.key_arn
  snapshot_retention_days          = var.snapshot_retention_days
  bandwidth_throttling_mbps        = var.bandwidth_throttling_mbps
  initialize_service               = var.initialize_drs_service
  use_private_ip                   = true
}
