output "dr_strategy" {
  description = "Active DR strategy."
  value       = var.dr_strategy
}

output "dr_capacity" {
  description = "Current DR web tier capacity (min / desired / max)."
  value       = local.dr_capacity
}

output "app_url" {
  description = "URL users should hit."
  value       = local.create_dns ? "https://${var.domain_name}" : "http://${module.app_primary.alb_dns_name}"
}

output "primary_region" {
  description = "Primary region."
  value       = var.primary_region
}

output "dr_region" {
  description = "DR region."
  value       = var.dr_region
}

output "primary_alb_dns_name" {
  description = "Primary ALB DNS name (test the primary site directly)."
  value       = module.app_primary.alb_dns_name
}

output "dr_alb_dns_name" {
  description = "DR ALB DNS name (test the DR site directly)."
  value       = local.deploy_dr ? module.app_dr[0].alb_dns_name : null
}

output "primary_asg_name" {
  description = "Primary Auto Scaling group."
  value       = module.app_primary.asg_name
}

output "dr_asg_name" {
  description = "DR Auto Scaling group."
  value       = local.deploy_dr ? module.app_dr[0].asg_name : null
}

output "production_capacity" {
  description = "Desired instance count the DR site must reach when activated."
  value       = var.primary_capacity.desired
}

output "global_cluster_id" {
  description = "Aurora Global Database identifier."
  value       = aws_rds_global_cluster.this.id
}

output "primary_db_cluster_arn" {
  description = "Primary Aurora cluster ARN."
  value       = aws_rds_cluster.primary.arn
}

output "dr_db_cluster_arn" {
  description = "DR Aurora cluster ARN."
  value       = local.deploy_dr ? aws_rds_cluster.dr[0].arn : null
}

output "db_secret_name" {
  description = "Secrets Manager secret holding the database credentials (replicated to the DR region)."
  value       = aws_secretsmanager_secret.db.name
}

output "backup_vault_primary" {
  description = "Primary AWS Backup vault."
  value       = aws_backup_vault.primary.name
}

output "backup_vault_dr" {
  description = "DR AWS Backup vault receiving cross-region copies."
  value       = aws_backup_vault.dr.name
}

output "failover_lambda_name" {
  description = "Failover Lambda in the DR region."
  value       = local.deploy_dr ? aws_lambda_function.failover[0].function_name : null
}

output "dashboard_url" {
  description = "CloudWatch dashboard showing both regions."
  value       = "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.dr.dashboard_name}"
}

output "fis_primary_outage_template_id" {
  description = "FIS template that simulates a primary site outage."
  value       = var.enable_chaos_experiments ? aws_fis_experiment_template.primary_outage[0].id : null
}

output "fis_terminate_instance_template_id" {
  description = "FIS template that terminates one primary web instance."
  value       = var.enable_chaos_experiments ? aws_fis_experiment_template.terminate_instance[0].id : null
}

output "fis_cpu_stress_template_id" {
  description = "FIS template that stresses CPU on the primary web tier."
  value       = var.enable_chaos_experiments ? aws_fis_experiment_template.cpu_stress[0].id : null
}
