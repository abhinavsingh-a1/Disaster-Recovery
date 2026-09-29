output "region" {
  value = var.region
}

output "project_name" {
  value = var.project_name
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "subnet_ids" {
  value = { for k, s in aws_subnet.this : k => "${s.id} (${s.availability_zone})" }
}

output "staging_subnet_id" {
  value = aws_subnet.this["staging"].id
}

output "recovery_subnet_id" {
  value = aws_subnet.this["recovery"].id
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "recovery_instance_type" {
  value = var.recovery_instance_type
}

output "source_instance_id" {
  value = aws_instance.source.id
}

output "source_url" {
  value = "http://${aws_instance.source.public_ip}/"
}

output "drs_replication_template_id" {
  value = aws_drs_replication_configuration_template.this.id
}

output "agent_access_key_id" {
  value     = try(aws_iam_access_key.drs_agent[0].id, "")
  sensitive = true
}

output "agent_secret_access_key" {
  value     = try(aws_iam_access_key.drs_agent[0].secret, "")
  sensitive = true
}

output "failback_access_key_id" {
  value     = try(aws_iam_access_key.drs_failback[0].id, "")
  sensitive = true
}

output "failback_secret_access_key" {
  value     = try(aws_iam_access_key.drs_failback[0].secret, "")
  sensitive = true
}

output "next_steps" {
  value = <<-EOT
    1. ./scripts/install-agent.sh        # install AWS Replication Agent on the source via SSM
    2. ./scripts/wait-for-sync.sh        # wait until DRS shows the server as Ready / CONTINUOUS
    3. ./scripts/configure-launch.sh     # recovery subnet, ${var.recovery_instance_type}, public IP, right-sizing off
    4. ./scripts/start-recovery.sh drill # or: recovery
    5. ./scripts/cleanup-drs.sh && terraform destroy
  EOT
}
