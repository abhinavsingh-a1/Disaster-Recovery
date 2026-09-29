output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "db_subnet_ids" {
  value = aws_subnet.db[*].id
}

output "staging_subnet_id" {
  value = var.create_staging_subnet ? aws_subnet.staging[0].id : null
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}
