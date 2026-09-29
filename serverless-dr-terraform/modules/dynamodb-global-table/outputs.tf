output "table_name" {
  value = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "ARN of the table in the provider's (primary) region."
  value       = aws_dynamodb_table.this.arn
}

output "replica_arns" {
  description = "Map of region => replica table ARN."
  value       = { for r in aws_dynamodb_table.this.replica : r.region_name => r.arn }
}
