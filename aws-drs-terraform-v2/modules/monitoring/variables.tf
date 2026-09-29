variable "name" {
  description = "Name prefix."
  type        = string
}

variable "alert_emails" {
  description = "Email subscribers."
  type        = list(string)
}

variable "max_lag_seconds" {
  description = "Replication lag alarm threshold."
  type        = number
}

variable "primary_alb_arn_suffix" {
  description = "Production ALB ARN suffix."
  type        = string
}

variable "primary_tg_arn_suffix" {
  description = "Production target group ARN suffix."
  type        = string
}

variable "drs_event_detail_types" {
  description = "DRS EventBridge detail-types that should page someone."
  type        = list(string)

  default = [
    "DRS Source Server Data Replication Stalled Change",
    "DRS Source Server Launch Result",
  ]
}
