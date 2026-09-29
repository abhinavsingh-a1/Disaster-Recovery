variable "table_name" {
  type = string
}

variable "replica_regions" {
  description = "Regions (other than the provider's region) that get a replica."
  type        = list(string)
}

variable "deletion_protection" {
  type    = bool
  default = false
}
