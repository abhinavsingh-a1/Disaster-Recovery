output "api_url" {
  description = "Single custom-domain endpoint (latency routed across both regions)."
  value       = "https://${local.api_domain_name}"
}

output "primary_invoke_url" {
  description = "Direct regional endpoint in the primary region (bypasses Route 53)."
  value       = module.api_primary.invoke_url
}

output "dr_invoke_url" {
  description = "Direct regional endpoint in the DR region (bypasses Route 53)."
  value       = module.api_dr.invoke_url
}

output "table_name" {
  value = module.global_table.table_name
}

output "table_arns" {
  description = "Each replica is its own regional table with its own ARN."
  value = {
    (var.primary_region) = module.global_table.table_arn
    (var.dr_region)      = module.global_table.replica_arns[var.dr_region]
  }
}

output "health_check_ids" {
  value = { for k, hc in aws_route53_health_check.api : k => hc.id }
}
