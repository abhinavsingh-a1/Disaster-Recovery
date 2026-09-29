variable "name" {
  description = "Name prefix."
  type        = string
}

variable "source_instance_ids" {
  description = "EC2 instance IDs of protected servers (used to find DRS source servers)."
  type        = list(string)
}

variable "recovery_subnet_ids" {
  description = "Private subnets for recovery instances (round-robin)."
  type        = list(string)
}

variable "recovery_security_group_id" {
  description = "Security group for recovery instances."
  type        = string
}

variable "recovery_instance_type" {
  description = "Instance type written to the DRS launch templates."
  type        = string
}

variable "target_group_arn" {
  description = "DR ALB target group that recovery instances are registered to."
  type        = string
}

variable "enable_database_failover" {
  description = "Create the FailoverDatabase runbook."
  type        = bool
}

variable "db_replica_identifier" {
  description = "RDS replica identifier."
  type        = string
}

variable "db_replica_address" {
  description = "RDS replica endpoint address."
  type        = string
}

variable "db_record_fqdn" {
  description = "Private DNS name apps use for the DB."
  type        = string
}

variable "private_zone_id" {
  description = "Private hosted zone ID."
  type        = string
}

variable "secret_name" {
  description = "DB secret name (replicated into the DR region)."
  type        = string
}
