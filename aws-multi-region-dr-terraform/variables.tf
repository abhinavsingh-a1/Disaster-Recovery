# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
variable "project_name" {
  description = "Short name used as a prefix for every resource."
  type        = string
  default     = "dr-demo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.project_name))
    error_message = "Use 3-16 lowercase letters, digits or hyphens (ALB and target group names are limited to 32 characters)."
  }
}

variable "primary_region" {
  description = "Region that serves production traffic in normal operation."
  type        = string
  default     = "eu-central-1"
}

variable "dr_region" {
  description = "Recovery region."
  type        = string
  default     = "eu-west-1"
}

# ---------------------------------------------------------------------------
# Disaster recovery strategy
# ---------------------------------------------------------------------------
variable "dr_strategy" {
  description = <<-EOT
    Which DR strategy to run in the recovery region:
      backup_restore - only cross-region backup copies (highest RPO/RTO, cheapest)
      pilot_light    - Aurora replica running, web tier at 0 instances
      warm_standby   - everything running at minimum size (1 instance)
      multi_site     - full capacity in both regions, active-active (lowest RTO, most expensive)
  EOT
  type        = string
  default     = "warm_standby"

  validation {
    condition     = contains(["backup_restore", "pilot_light", "warm_standby", "multi_site"], var.dr_strategy)
    error_message = "dr_strategy must be one of: backup_restore, pilot_light, warm_standby, multi_site."
  }
}

variable "dr_activate" {
  description = "Set to true during/after a disaster so Terraform keeps the DR web tier at production capacity."
  type        = bool
  default     = false
}

variable "auto_failover_enabled" {
  description = "false = the failover Lambda only reports what it would do (human in the loop). true = it promotes Aurora and scales the DR web tier by itself."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
variable "primary_vpc_cidr" {
  description = "CIDR block of the primary VPC."
  type        = string
  default     = "10.10.0.0/16"
}

variable "dr_vpc_cidr" {
  description = "CIDR block of the DR VPC (must not overlap the primary one)."
  type        = string
  default     = "10.20.0.0/16"
}

# ---------------------------------------------------------------------------
# Web tier
# ---------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type for the web tier in both regions."
  type        = string
  default     = "t3.micro"
}

variable "primary_capacity" {
  description = "Auto Scaling capacity of the primary site (also the DR target size when activated or in multi_site)."
  type = object({
    min     = number
    desired = number
    max     = number
  })
  default = {
    min     = 2
    desired = 2
    max     = 6
  }

  validation {
    condition     = var.primary_capacity.min >= 1 && var.primary_capacity.min <= var.primary_capacity.desired && var.primary_capacity.desired <= var.primary_capacity.max
    error_message = "primary_capacity must satisfy 1 <= min <= desired <= max."
  }
}

variable "alb_deletion_protection" {
  description = "Enable deletion protection on both ALBs."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Database tier (Aurora Global Database)
# ---------------------------------------------------------------------------
variable "db_engine_version" {
  description = "Aurora MySQL engine version. Must support Global Database in both regions (see docs/runbook.md)."
  type        = string
  default     = "8.0.mysql_aurora.3.08.0"
}

variable "db_instance_class" {
  description = "Aurora instance class. Global Database does not support burstable (db.t*) classes."
  type        = string
  default     = "db.r6g.large"
}

variable "db_instances_per_region" {
  description = "Aurora instances per regional cluster. Use 2 for Multi-AZ high availability inside a region."
  type        = number
  default     = 1

  validation {
    condition     = var.db_instances_per_region >= 1 && var.db_instances_per_region <= 3
    error_message = "db_instances_per_region must be between 1 and 3."
  }
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "db_master_username" {
  description = "Aurora master username."
  type        = string
  default     = "dbadmin"
}

variable "db_deletion_protection" {
  description = "Enable deletion protection on the Aurora clusters. Keep false for demos so `terraform destroy` works."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# DNS and TLS (optional)
# ---------------------------------------------------------------------------
variable "hosted_zone_id" {
  description = "Existing Route 53 public hosted zone ID. When set, DNS failover records and HTTPS (ACM) are created."
  type        = string
  default     = null
}

variable "domain_name" {
  description = "Application hostname inside the hosted zone, e.g. app.example.com."
  type        = string
  default     = null

  validation {
    condition     = var.hosted_zone_id == null || var.domain_name != null
    error_message = "domain_name must be set when hosted_zone_id is set."
  }
}

variable "health_check_interval" {
  description = "Route 53 health check interval in seconds (10 = fast detection, costs extra; 30 = standard)."
  type        = number
  default     = 10

  validation {
    condition     = contains([10, 30], var.health_check_interval)
    error_message = "health_check_interval must be 10 or 30."
  }
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------
variable "alert_email" {
  description = "E-mail address for alarm notifications (one confirmation mail per region topic). null = no subscription."
  type        = string
  default     = null
}

variable "replication_lag_alarm_ms" {
  description = "Alarm when Aurora Global Database replication lag exceeds this many milliseconds (this is your live RPO)."
  type        = number
  default     = 2000
}

# ---------------------------------------------------------------------------
# AWS Backup
# ---------------------------------------------------------------------------
variable "backup_schedule" {
  description = "AWS Backup schedule (cron in UTC). Determines the RPO of the backup_restore strategy."
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "backup_retention_days" {
  description = "Days to keep recovery points in the primary vault."
  type        = number
  default     = 35
}

variable "dr_copy_retention_days" {
  description = "Days to keep the cross-region copies in the DR vault."
  type        = number
  default     = 35
}

variable "enable_vault_lock" {
  description = "Apply AWS Backup Vault Lock (WORM, governance mode) to the DR vault."
  type        = bool
  default     = false
}

variable "vault_lock_min_retention_days" {
  description = "Vault Lock minimum retention. Must be <= dr_copy_retention_days."
  type        = number
  default     = 7
}

variable "vault_lock_max_retention_days" {
  description = "Vault Lock maximum retention. Must be >= dr_copy_retention_days."
  type        = number
  default     = 365
}

# ---------------------------------------------------------------------------
# Chaos engineering
# ---------------------------------------------------------------------------
variable "enable_chaos_experiments" {
  description = "Create AWS FIS experiment templates. Templates cost nothing until an experiment is started."
  type        = bool
  default     = true
}
