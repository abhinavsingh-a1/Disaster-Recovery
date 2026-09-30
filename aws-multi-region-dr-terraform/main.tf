# ---------------------------------------------------------------------------
# Networking - one VPC per region. The DR VPC always exists (it is cheap)
# so backups can be restored into it even with backup_restore.
# ---------------------------------------------------------------------------
module "network_primary" {
  source    = "./modules/network"
  providers = { aws = aws.primary }

  name = "${local.name}-primary"
  cidr = var.primary_vpc_cidr
}

module "network_dr" {
  source    = "./modules/network"
  providers = { aws = aws.dr }

  name = "${local.name}-dr"
  cidr = var.dr_vpc_cidr

  # backup_restore runs no instances in DR, so skip the NAT gateway there
  enable_nat_gateway = local.deploy_dr
}

# ---------------------------------------------------------------------------
# Web tier - ALB (public subnets) + Auto Scaling group (private subnets)
# ---------------------------------------------------------------------------
module "app_primary" {
  source    = "./modules/app"
  providers = { aws = aws.primary }

  name                = "${local.name}-primary"
  project_name        = var.project_name
  site_role           = "primary"
  vpc_id              = module.network_primary.vpc_id
  alb_subnet_ids      = module.network_primary.public_subnet_ids
  instance_subnet_ids = module.network_primary.app_subnet_ids
  instance_type       = var.instance_type

  min_size         = var.primary_capacity.min
  desired_capacity = var.primary_capacity.desired
  max_size         = var.primary_capacity.max

  enable_https            = local.create_dns
  certificate_arn         = local.create_dns ? aws_acm_certificate_validation.primary[0].certificate_arn : null
  alb_deletion_protection = var.alb_deletion_protection

  app_source       = local.app_source
  db_host          = aws_rds_cluster.primary.endpoint
  db_secret_name   = aws_secretsmanager_secret.db.name
  write_forwarding = false
  alarm_topic_arn  = aws_sns_topic.alerts_primary.arn
}

module "app_dr" {
  count     = local.deploy_dr ? 1 : 0
  source    = "./modules/app"
  providers = { aws = aws.dr }

  name                = "${local.name}-dr"
  project_name        = var.project_name
  site_role           = "dr"
  vpc_id              = module.network_dr.vpc_id
  alb_subnet_ids      = module.network_dr.public_subnet_ids
  instance_subnet_ids = module.network_dr.app_subnet_ids
  instance_type       = var.instance_type

  min_size         = local.dr_capacity.min
  desired_capacity = local.dr_capacity.desired
  max_size         = local.dr_capacity.max

  enable_https            = local.create_dns
  certificate_arn         = local.create_dns ? aws_acm_certificate_validation.dr[0].certificate_arn : null
  alb_deletion_protection = var.alb_deletion_protection

  app_source = local.app_source
  # The secondary cluster endpoint is read-only until promoted; after promotion
  # the same DNS name becomes the writer, so the app needs no reconfiguration.
  db_host          = aws_rds_cluster.dr[0].endpoint
  db_secret_name   = aws_secretsmanager_secret.db.name # replicated to the DR region
  write_forwarding = local.active_active
  alarm_topic_arn  = aws_sns_topic.alerts_dr.arn
}
