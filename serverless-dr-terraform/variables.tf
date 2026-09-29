variable "project_name" {
  description = "Prefix used for all resource names."
  type        = string
  default     = "notes-dr"
}

variable "primary_region" {
  description = "Primary region (us-east-1 / N. Virginia in the talk)."
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "DR region (us-east-2 / Ohio in the talk). Also active: this is active/active."
  type        = string
  default     = "us-east-2"
}

variable "hosted_zone_name" {
  description = "Existing public Route 53 hosted zone, e.g. example.com"
  type        = string
}

variable "api_subdomain" {
  description = "Subdomain for the API. Final FQDN = <api_subdomain>.<hosted_zone_name>"
  type        = string
  default     = "api"
}

variable "stage_name" {
  description = "API Gateway stage name."
  type        = string
  default     = "dev"
}

variable "table_name" {
  description = "DynamoDB global table name. Identical in every region."
  type        = string
  default     = "notes-dr-notes"
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the Lambda functions."
  type        = number
  default     = 14
}

variable "enable_health_checks" {
  description = "Attach Route 53 HTTPS health checks (/health) to the latency records."
  type        = bool
  default     = true
}

variable "simulate_primary_failure" {
  description = "Failover drill: inverts the primary health check so Route 53 treats the primary region as unhealthy and sends all traffic to the DR region."
  type        = bool
  default     = false
}

variable "replication_latency_threshold_ms" {
  description = "Alarm when average DynamoDB ReplicationLatency exceeds this value (ms)."
  type        = number
  default     = 1000
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic (in the primary region) for alarm notifications."
  type        = string
  default     = ""
}
