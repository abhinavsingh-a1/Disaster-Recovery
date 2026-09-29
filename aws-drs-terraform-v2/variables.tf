# ---------------- General ----------------
variable "project_name" {
  description = "Name prefix for all resources (lowercase, digits, hyphens)."
  type        = string
  default     = "drs-lab"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 3-21 chars: lowercase letters, digits, hyphens."
  }
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}

# ---------------- Regions / DR topology ----------------
variable "primary_region" {
  description = "Region hosting production."
  type        = string
  default     = "us-east-1"
}

variable "dr_mode" {
  description = "cross-region (survives a Region outage) or cross-az (cheaper, same Region, different AZs)."
  type        = string
  default     = "cross-region"

  validation {
    condition     = contains(["cross-region", "cross-az"], var.dr_mode)
    error_message = "dr_mode must be cross-region or cross-az."
  }
}

variable "dr_region" {
  description = "Recovery Region used when dr_mode = cross-region. Must support AWS DRS."
  type        = string
  default     = "us-east-2"

  validation {
    condition     = var.dr_mode == "cross-az" || var.dr_region != var.primary_region
    error_message = "In cross-region mode dr_region must differ from primary_region."
  }
}

# ---------------- Networking ----------------
variable "primary_vpc_cidr" {
  description = "CIDR of the production VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "dr_vpc_cidr" {
  description = "CIDR of the recovery VPC (must not overlap primary_vpc_cidr)."
  type        = string
  default     = "10.30.0.0/16"
}

variable "dr_enable_nat_gateway" {
  description = "NAT gateway in the DR VPC (outbound internet for staging/recovery subnets)."
  type        = bool
  default     = true
}

variable "dr_enable_vpc_endpoints" {
  description = "Interface/gateway VPC endpoints in the DR VPC (private access to DRS, EC2, SSM, S3...)."
  type        = bool
  default     = false

  validation {
    condition     = var.dr_enable_vpc_endpoints || var.dr_enable_nat_gateway
    error_message = "The DR VPC needs either a NAT gateway or VPC endpoints so replication servers can reach AWS APIs."
  }
}

variable "enable_flow_logs" {
  description = "VPC flow logs to CloudWatch Logs for both VPCs."
  type        = bool
  default     = true
}

variable "allowed_http_cidrs" {
  description = "CIDRs allowed to reach the public load balancers."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "certificate_arn_primary" {
  description = "Optional ACM certificate ARN (primary region) to enable HTTPS on the production ALB."
  type        = string
  default     = null
}

variable "certificate_arn_dr" {
  description = "Optional ACM certificate ARN (DR region) to enable HTTPS on the DR ALB."
  type        = string
  default     = null
}

# ---------------- Protected servers ----------------
variable "protected_servers" {
  description = "Servers to protect with DRS. Key = server name."

  type = map(object({
    instance_type    = optional(string, "t3.micro")
    az_index         = optional(number, 0)
    root_volume_size = optional(number, 8)
  }))
  default = {
    web-1 = {}
  }

  validation {
    condition     = length(var.protected_servers) > 0 && alltrue([for s in values(var.protected_servers) : contains([0, 1], s.az_index)])
    error_message = "Define at least one server; az_index must be 0 or 1."
  }
}

variable "install_drs_agent" {
  description = "Install the AWS Replication Agent on protected servers via user_data."
  type        = bool
  default     = true
}

# ---------------- DRS replication ----------------
variable "initialize_drs_service" {
  description = "Run 'aws drs initialize-service' (requires AWS CLI where Terraform runs)."
  type        = bool
  default     = true
}

variable "replication_server_instance_type" {
  description = "Instance type of DRS replication servers."
  type        = string
  default     = "t3.small"
}

variable "recovery_instance_type" {
  description = "Instance type for drill/recovery instances (right-sizing disabled)."
  type        = string
  default     = "t3.micro"
}

variable "snapshot_retention_days" {
  description = "Point-in-time snapshot retention (days). >= 7 recommended for ransomware scenarios."
  type        = number
  default     = 7

  validation {
    condition     = var.snapshot_retention_days >= 1 && var.snapshot_retention_days <= 365
    error_message = "snapshot_retention_days must be between 1 and 365."
  }
}

variable "bandwidth_throttling_mbps" {
  description = "Replication bandwidth cap in Mbps (0 = unlimited)."
  type        = number
  default     = 0
}

# ---------------- Database tier ----------------
variable "enable_database" {
  description = "Deploy RDS PostgreSQL with a cross-region (or cross-AZ) read replica and DB failover runbook."
  type        = bool
  default     = true
}

variable "db_engine_version" {
  description = "PostgreSQL major/minor version."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "RDS instance class for primary and replica."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "Multi-AZ for the primary database."
  type        = bool
  default     = true
}

variable "db_deletion_protection" {
  description = "Deletion protection for the primary database (set true for production)."
  type        = bool
  default     = false
}

# ---------------- Backup / ransomware ----------------
variable "backup_retention_days" {
  description = "Retention of AWS Backup recovery points (primary and DR copies)."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 7
    error_message = "backup_retention_days must be >= 7."
  }
}

variable "backup_vault_lock_mode" {
  description = "none | governance | compliance. compliance becomes IMMUTABLE after the grace period."
  type        = string
  default     = "governance"

  validation {
    condition     = contains(["none", "governance", "compliance"], var.backup_vault_lock_mode)
    error_message = "backup_vault_lock_mode must be none, governance or compliance."
  }
}

variable "backup_compliance_changeable_days" {
  description = "Grace period (days) before a compliance-mode vault lock becomes immutable."
  type        = number
  default     = 3
}

# ---------------- Monitoring ----------------
variable "alert_emails" {
  description = "Email addresses subscribed to DR alerts (confirm the subscription email)."
  type        = list(string)
  default     = []
}

variable "max_replication_lag_seconds" {
  description = "Alarm threshold for DRS replication lag."
  type        = number
  default     = 300
}

# ---------------- DNS failover ----------------
variable "hosted_zone_id" {
  description = "Public Route 53 hosted zone ID. null disables DNS failover."
  type        = string
  default     = null
}

variable "dns_record_name" {
  description = "Record for the application, e.g. app.example.com (required with hosted_zone_id)."
  type        = string
  default     = null

  validation {
    condition     = var.hosted_zone_id == null || var.dns_record_name != null
    error_message = "dns_record_name is required when hosted_zone_id is set."
  }
}

variable "auto_recovery_enabled" {
  description = "Automatically start the recovery (and DB failover) runbooks when the primary health check alarms."
  type        = bool
  default     = false
}

variable "failover_evaluation_minutes" {
  description = "Consecutive failed minutes before the health-check alarm (and auto recovery) fires."
  type        = number
  default     = 3
}
