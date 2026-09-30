variable "project_name" {
  description = "Prefix for the state bucket name."
  type        = string
  default     = "dr-demo"
}

variable "region" {
  description = <<-EOT
    Region for the state bucket. Defaults to the DR region on purpose: if the
    primary region fails, you can still run Terraform from the DR region.
  EOT
  type        = string
  default     = "eu-west-1"
}
