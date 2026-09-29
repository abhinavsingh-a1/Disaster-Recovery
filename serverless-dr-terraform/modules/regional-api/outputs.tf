output "region" {
  value = local.region
}

output "invoke_url" {
  description = "Direct regional URL, e.g. https://abc123.execute-api.us-east-1.amazonaws.com/dev"
  value       = aws_api_gateway_stage.this.invoke_url
}

output "execute_api_host" {
  description = "Hostname used by the Route 53 health check."
  value       = "${aws_api_gateway_rest_api.this.id}.execute-api.${local.region}.amazonaws.com"
}

output "regional_domain_name" {
  description = "Alias target for Route 53 (d-xxxx.execute-api.<region>.amazonaws.com)."
  value       = aws_api_gateway_domain_name.api.regional_domain_name
}

output "regional_zone_id" {
  value = aws_api_gateway_domain_name.api.regional_zone_id
}
