variable "region" {
  description = "AWS region for source, staging and recovery (the video uses us-east-1 / N. Virginia)."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix and Project tag for all resources."
  type        = string
  default     = "drs-demo"
}

variable "extra_tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}

# ---------------- Network ----------------
variable "vpc_cidr" {
  description = "CIDR of the demo VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "source_az_suffix" {
  description = "AZ letter for the source subnet (video: a)."
  type        = string
  default     = "a"
}

variable "staging_az_suffix" {
  description = "AZ letter for the DRS staging subnet (video: b)."
  type        = string
  default     = "b"
}

variable "recovery_az_suffix" {
  description = "AZ letter for the recovery subnet (video: f). Change it if the recovery instance type is not offered in that AZ."
  type        = string
  default     = "f"
}

variable "http_ingress_cidrs" {
  description = "CIDRs allowed to reach the demo web page on port 80 (source and recovery servers)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_ingress_cidrs" {
  description = "CIDRs allowed to SSH (22). Empty = no SSH; use SSM Session Manager instead."
  type        = list(string)
  default     = []
}

# ---------------- Source server ----------------
variable "source_instance_type" {
  description = "Instance type of the demo source server."
  type        = string
  default     = "t3.micro"
}

variable "source_root_volume_gb" {
  description = "Root volume size of the source server (video: 8 GB)."
  type        = number
  default     = 8
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access."
  type        = string
  default     = null
}

# ---------------- DRS replication settings ----------------
variable "initialize_drs" {
  description = "Run `aws drs initialize-service` once for the region (needs AWS CLI on the machine running Terraform)."
  type        = bool
  default     = true
}

variable "replication_server_instance_type" {
  description = "Replication server instance type (video: default t3.small)."
  type        = string
  default     = "t3.small"
}

variable "staging_disk_type" {
  description = "EBS type for staging disks: GP2 (video choice, cheaper), GP3, ST1 or AUTO."
  type        = string
  default     = "GP2"

  validation {
    condition     = contains(["GP2", "GP3", "ST1", "AUTO"], var.staging_disk_type)
    error_message = "staging_disk_type must be GP2, GP3, ST1 or AUTO."
  }
}

variable "bandwidth_throttling_mbps" {
  description = "Replication bandwidth cap in Mbps. 0 = no throttling."
  type        = number
  default     = 0
}

variable "use_private_ip_for_replication" {
  description = "Replicate over private IP (VPN / Direct Connect / peering). The video uses public IP."
  type        = bool
  default     = false
}

variable "pit_retention_days" {
  description = "Days the daily point-in-time snapshots are kept (video: 7)."
  type        = number
  default     = 7
}

# ---------------- Recovery (launch) settings ----------------
variable "recovery_instance_type" {
  description = "Instance type of the launched recovery server (video: c5.large). Applied by scripts/configure-launch.sh."
  type        = string
  default     = "c5.large"
}

# ---------------- IAM ----------------
variable "create_agent_access_key" {
  description = "Create an access key for the agent-installer IAM user. Set to false and re-apply once the agent is installed."
  type        = bool
  default     = true
}

variable "create_failback_user" {
  description = "Create the IAM user used by the DRS Failback Client (needed only for failback)."
  type        = bool
  default     = false
}
