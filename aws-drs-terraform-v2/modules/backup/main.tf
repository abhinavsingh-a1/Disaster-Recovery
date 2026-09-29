variable "name" {
  description = "Name prefix."
  type        = string
}

variable "primary_kms_key_arn" {
  description = "CMK for the primary vault."
  type        = string
}

variable "dr_kms_key_arn" {
  description = "CMK for the DR vault."
  type        = string
}

variable "retention_days" {
  description = "Recovery point retention."
  type        = number
}

variable "vault_lock_mode" {
  description = "none | governance | compliance."
  type        = string
}

variable "compliance_changeable_days" {
  description = "Grace period for compliance mode."
  type        = number
}

locals {
  lock_enabled = var.vault_lock_mode != "none"
}

resource "aws_backup_vault" "primary" {
  name          = "${var.name}-primary"
  kms_key_arn   = var.primary_kms_key_arn
  force_destroy = !local.lock_enabled
}

resource "aws_backup_vault" "dr" {
  provider      = aws.dr
  name          = "${var.name}-dr"
  kms_key_arn   = var.dr_kms_key_arn
  force_destroy = !local.lock_enabled
}

# Vault Lock: recovery points cannot be deleted (even by admins in compliance
# mode) before min_retention_days - protects backups from ransomware/insiders.
resource "aws_backup_vault_lock_configuration" "primary" {
  count               = local.lock_enabled ? 1 : 0
  backup_vault_name   = aws_backup_vault.primary.name
  min_retention_days  = var.retention_days
  max_retention_days  = 365
  changeable_for_days = var.vault_lock_mode == "compliance" ? var.compliance_changeable_days : null
}

resource "aws_backup_vault_lock_configuration" "dr" {
  provider            = aws.dr
  count               = local.lock_enabled ? 1 : 0
  backup_vault_name   = aws_backup_vault.dr.name
  min_retention_days  = var.retention_days
  max_retention_days  = 365
  changeable_for_days = var.vault_lock_mode == "compliance" ? var.compliance_changeable_days : null
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.name}-aws-backup"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_plan" "this" {
  name = "${var.name}-daily"

  rule {
    rule_name         = "daily-with-dr-copy"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 3 * * ? *)"
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.retention_days
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn
      lifecycle {
        delete_after = var.retention_days
      }
    }
  }
}

# Everything tagged Backup=true (protected servers, primary DB)
resource "aws_backup_selection" "tagged" {
  name         = "${var.name}-tagged"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}

output "vault_names" {
  value = {
    primary = aws_backup_vault.primary.name
    dr      = aws_backup_vault.dr.name
  }
}
