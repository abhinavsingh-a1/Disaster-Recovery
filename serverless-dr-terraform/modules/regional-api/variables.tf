variable "name_prefix" {
  type = string
}

variable "stage_name" {
  type = string
}

variable "table_name" {
  description = "Global table name (identical in every region)."
  type        = string
}

variable "domain_name" {
  description = "Custom domain shared by all regions, e.g. api.example.com"
  type        = string
}

variable "hosted_zone_id" {
  type = string
}

variable "lambda_zip_path" {
  type = string
}

variable "lambda_zip_hash" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 14
}
