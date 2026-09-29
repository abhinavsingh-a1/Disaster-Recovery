variable "name" {
  description = "Name prefix."
  type        = string
}

variable "hosted_zone_id" {
  description = "Public hosted zone."
  type        = string
}

variable "record_name" {
  description = "Application record (e.g. app.example.com)."
  type        = string
}

variable "primary_alb_dns_name" {
  description = "Production ALB DNS name."
  type        = string
}

variable "primary_alb_zone_id" {
  description = "Production ALB hosted zone ID."
  type        = string
}

variable "primary_uses_https" {
  description = "Health check over HTTPS."
  type        = bool
}

variable "dr_alb_dns_name" {
  description = "DR ALB DNS name."
  type        = string
}

variable "dr_alb_zone_id" {
  description = "DR ALB hosted zone ID."
  type        = string
}

variable "alert_emails" {
  description = "Email subscribers for failover alerts."
  type        = list(string)
}

variable "evaluation_minutes" {
  description = "Failed minutes before alarm."
  type        = number
}

variable "auto_recovery_enabled" {
  description = "Start DR runbooks automatically on alarm."
  type        = bool
}

variable "dr_region" {
  description = "Region of the DR runbooks."
  type        = string
}

variable "automation_role_arn" {
  description = "Role the runbooks assume (passed by the Lambda)."
  type        = string
}

variable "recover_document_name" {
  description = "Recover runbook name."
  type        = string
}

variable "database_document_name" {
  description = "FailoverDatabase runbook name, or empty."
  type        = string
}

variable "health_check_path" {
  description = "Path probed by Route 53."
  type        = string
  default     = "/health.html"
}
