module "dr_automation" {
  source    = "./modules/dr-automation"
  providers = { aws = aws.dr }

  name                       = local.name
  source_instance_ids        = local.source_instance_ids
  recovery_subnet_ids        = module.network_dr.app_subnet_ids
  recovery_security_group_id = aws_security_group.recovery.id
  recovery_instance_type     = var.recovery_instance_type
  target_group_arn           = module.web_alb_dr.target_group_arn

  enable_database_failover = var.enable_database
  db_replica_identifier    = var.enable_database ? module.database[0].replica_identifier : ""
  db_replica_address       = var.enable_database ? module.database[0].replica_address : ""
  db_record_fqdn           = var.enable_database ? module.database[0].db_fqdn : ""
  private_zone_id          = var.enable_database ? module.database[0].private_zone_id : ""
  secret_name              = var.enable_database ? module.database[0].secret_name : ""
}

module "monitoring" {
  source = "./modules/monitoring"

  providers = {
    aws         = aws.dr
    aws.primary = aws
  }

  name                   = local.name
  alert_emails           = var.alert_emails
  max_lag_seconds        = var.max_replication_lag_seconds
  primary_alb_arn_suffix = module.web_alb_primary.arn_suffix
  primary_tg_arn_suffix  = module.web_alb_primary.target_group_arn_suffix
}

module "failover_dns" {
  source    = "./modules/failover-dns"
  count     = var.hosted_zone_id == null ? 0 : 1
  providers = { aws = aws.global }

  name                   = local.name
  hosted_zone_id         = var.hosted_zone_id
  record_name            = var.dns_record_name
  primary_alb_dns_name   = module.web_alb_primary.dns_name
  primary_alb_zone_id    = module.web_alb_primary.zone_id
  primary_uses_https     = var.certificate_arn_primary != null
  dr_alb_dns_name        = module.web_alb_dr.dns_name
  dr_alb_zone_id         = module.web_alb_dr.zone_id
  alert_emails           = var.alert_emails
  evaluation_minutes     = var.failover_evaluation_minutes
  auto_recovery_enabled  = var.auto_recovery_enabled
  dr_region              = local.dr_region
  automation_role_arn    = module.dr_automation.automation_role_arn
  recover_document_name  = module.dr_automation.document_names.recover
  database_document_name = var.enable_database ? module.dr_automation.document_names.failover_database : ""
}
