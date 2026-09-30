output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnets (ALB, NAT)."
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "Private web-tier subnets."
  value       = aws_subnet.app[*].id
}

output "app_subnet_arns" {
  description = "Private web-tier subnet ARNs (targets for chaos experiments)."
  value       = aws_subnet.app[*].arn
}

output "db_subnet_ids" {
  description = "Isolated database subnets."
  value       = aws_subnet.db[*].id
}
