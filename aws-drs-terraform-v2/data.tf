module "database" {
  source = "./modules/database"
  count  = var.enable_database ? 1 : 0

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  name                   = local.name
  same_region            = local.same_region
  dr_region              = local.dr_region
  engine_version         = var.db_engine_version
  instance_class         = var.db_instance_class
  multi_az               = var.db_multi_az
  deletion_protection    = var.db_deletion_protection
  backup_retention_days  = 7
  primary_vpc_id         = module.network_primary.vpc_id
  primary_db_subnet_ids  = module.network_primary.db_subnet_ids
  primary_allowed_sg_ids = [aws_security_group.app_primary.id]
  primary_kms_key_arn    = module.kms_primary.key_arn
  dr_vpc_id              = module.network_dr.vpc_id
  dr_db_subnet_ids       = module.network_dr.db_subnet_ids
  dr_allowed_sg_ids      = [aws_security_group.recovery.id]
  dr_kms_key_arn         = module.kms_dr.key_arn
  private_zone_name      = "${local.name}.internal"
}

module "backup" {
  source = "./modules/backup"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  name                       = local.name
  primary_kms_key_arn        = module.kms_primary.key_arn
  dr_kms_key_arn             = module.kms_dr.key_arn
  retention_days             = var.backup_retention_days
  vault_lock_mode            = var.backup_vault_lock_mode
  compliance_changeable_days = var.backup_compliance_changeable_days
}
