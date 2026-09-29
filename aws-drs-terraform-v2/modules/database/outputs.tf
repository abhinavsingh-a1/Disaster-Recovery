output "secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  value = aws_secretsmanager_secret.db.name
}

output "db_fqdn" {
  value = local.db_fqdn
}

output "private_zone_id" {
  value = aws_route53_zone.private.zone_id
}

output "primary_identifier" {
  value = aws_db_instance.primary.identifier
}

output "replica_identifier" {
  value = aws_db_instance.replica.identifier
}

output "replica_address" {
  value = aws_db_instance.replica.address
}
