output "automation_role_arn" {
  value = aws_iam_role.automation.arn
}

output "recovery_instance_profile_arn" {
  value = aws_iam_instance_profile.recovery.arn
}

output "document_names" {
  value = {
    prepare           = aws_ssm_document.prepare.name
    recover           = aws_ssm_document.recover.name
    failback          = aws_ssm_document.failback.name
    terminate_drills  = aws_ssm_document.terminate_drills.name
    failover_database = var.enable_database_failover ? aws_ssm_document.failover_database[0].name : ""
  }
}
