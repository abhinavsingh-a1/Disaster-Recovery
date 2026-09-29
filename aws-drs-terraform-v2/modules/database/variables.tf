variable "name" {
  description = "Name prefix."
  type        = string
}

variable "same_region" {
  description = "true in cross-az mode (replica in the same Region)."
  type        = bool
}

variable "dr_region" {
  description = "Region of the read replica."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL version."
  type        = string
}

variable "instance_class" {
  description = "Instance class."
  type        = string
}

variable "multi_az" {
  description = "Multi-AZ primary."
  type        = bool
}

variable "deletion_protection" {
  description = "Deletion protection on the primary."
  type        = bool
}

variable "backup_retention_days" {
  description = "Automated backup retention (required for replicas)."
  type        = number
}

variable "primary_vpc_id" {
  description = "Primary VPC."
  type        = string
}

variable "primary_db_subnet_ids" {
  description = "Primary DB subnets."
  type        = list(string)
}

variable "primary_allowed_sg_ids" {
  description = "SGs allowed to connect to the primary."
  type        = list(string)
}

variable "primary_kms_key_arn" {
  description = "CMK for the primary."
  type        = string
}

variable "dr_vpc_id" {
  description = "DR VPC."
  type        = string
}

variable "dr_db_subnet_ids" {
  description = "DR DB subnets."
  type        = list(string)
}

variable "dr_allowed_sg_ids" {
  description = "SGs allowed to connect to the replica."
  type        = list(string)
}

variable "dr_kms_key_arn" {
  description = "CMK for the replica (DR region)."
  type        = string
}

variable "private_zone_name" {
  description = "Private hosted zone shared by both VPCs, e.g. drs-lab.internal."
  type        = string
}
