output "dr_mode" {
  value = var.dr_mode
}

output "primary_region" {
  value = var.primary_region
}

output "effective_dr_region" {
  description = "Region where replication lands and recovery happens."
  value       = local.dr_region
}

output "failback_staging_enabled" {
  value = !local.same_region
}

output "data_plane_routing" {
  value = "PRIVATE_IP"
}

output "pit_retention_days" {
  value = var.snapshot_retention_days
}

output "protected_server_names" {
  value = sort(keys(var.protected_servers))
}

output "protected_instance_ids" {
  value = { for k, m in module.protected_server : k => m.instance_id }
}

output "primary_url" {
  value = module.web_alb_primary.url
}

output "dr_url" {
  description = "Serves traffic only after a recovery registered targets."
  value       = module.web_alb_dr.url
}

output "app_url" {
  value = var.hosted_zone_id == null ? module.web_alb_primary.url : "http://${var.dns_record_name}"
}

output "failover_dns_enabled" {
  value = var.hosted_zone_id != null
}

output "automation_documents" {
  description = "SSM Automation runbooks in the DR region."
  value       = module.dr_automation.document_names
}

output "dr_target_group_arn" {
  value = module.web_alb_dr.target_group_arn
}

output "alert_topics" {
  value = module.monitoring.topic_arns
}

output "database" {
  value = var.enable_database ? {
    endpoint_fqdn      = module.database[0].db_fqdn
    primary_identifier = module.database[0].primary_identifier
    replica_identifier = module.database[0].replica_identifier
    secret_name        = module.database[0].secret_name
  } : null
}

output "backup_vaults" {
  value = module.backup.vault_names
}
