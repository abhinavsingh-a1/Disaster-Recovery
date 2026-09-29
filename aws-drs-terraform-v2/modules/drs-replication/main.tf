variable "name" {
  description = "Name prefix."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the staging area."
  type        = string
}

variable "staging_subnet_id" {
  description = "Subnet where DRS launches replication servers and staging disks."
  type        = string
}

variable "allowed_replication_cidrs" {
  description = "CIDRs of source servers allowed to send replication data (TCP 1500)."
  type        = list(string)
}

variable "replication_server_instance_type" {
  description = "Replication server instance type."
  type        = string
}

variable "kms_key_arn" {
  description = "CMK for staging disks and PIT snapshots."
  type        = string
}

variable "snapshot_retention_days" {
  description = "Daily PIT snapshot retention."
  type        = number
}

variable "bandwidth_throttling_mbps" {
  description = "Replication bandwidth cap (0 = unlimited)."
  type        = number
}

variable "initialize_service" {
  description = "Initialize DRS in this region via AWS CLI."
  type        = bool
}

variable "use_private_ip" {
  description = "Replicate over private IPs (peering/VPN/DX) instead of public IPs."
  type        = bool
}

data "aws_region" "current" {}

# DRS initialization (creates service roles). Idempotent: if it fails because the
# service is already initialized, the describe call succeeds and apply continues.
resource "terraform_data" "init" {
  count            = var.initialize_service ? 1 : 0
  triggers_replace = [data.aws_region.current.region]

  provisioner "local-exec" {
    command = "aws drs initialize-service --region ${data.aws_region.current.region} || aws drs describe-replication-configuration-templates --region ${data.aws_region.current.region} > /dev/null"
  }
}

resource "aws_security_group" "replication" {
  name        = "${var.name}-replication-servers"
  description = "DRS replication servers"
  vpc_id      = var.vpc_id

  ingress {
    description = "DRS replication data"
    from_port   = 1500
    to_port     = 1500
    protocol    = "tcp"
    cidr_blocks = var.allowed_replication_cidrs
  }

  egress {
    description = "HTTPS to DRS, EC2 and S3 endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_drs_replication_configuration_template" "this" {
  staging_area_subnet_id                  = var.staging_subnet_id
  replication_server_instance_type        = var.replication_server_instance_type
  use_dedicated_replication_server        = false
  default_large_staging_disk_type         = "GP3"
  ebs_encryption                          = "CUSTOM"
  ebs_encryption_key_arn                  = var.kms_key_arn
  associate_default_security_group        = false
  replication_servers_security_groups_ids = [aws_security_group.replication.id]
  bandwidth_throttling                    = var.bandwidth_throttling_mbps
  create_public_ip                        = !var.use_private_ip
  data_plane_routing                      = var.use_private_ip ? "PRIVATE_IP" : "PUBLIC_IP"

  staging_area_tags = {
    Name = "${var.name}-staging"
    Role = "drs-staging"
  }

  pit_policy {
    rule_id            = 1
    enabled            = true
    interval           = 10
    retention_duration = 60
    units              = "MINUTE"
  }

  pit_policy {
    rule_id            = 2
    enabled            = true
    interval           = 1
    retention_duration = 24
    units              = "HOUR"
  }

  pit_policy {
    rule_id            = 3
    enabled            = true
    interval           = 1
    retention_duration = var.snapshot_retention_days
    units              = "DAY"
  }

  depends_on = [terraform_data.init]
}

output "template_id" {
  value = aws_drs_replication_configuration_template.this.id
}

output "security_group_id" {
  value = aws_security_group.replication.id
}
