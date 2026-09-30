# ---------------------------------------------------------------------------
# AWS Backup - the "backup and restore" layer, deployed under every strategy.
# Daily backup of everything tagged Backup=true, copied to the DR region.
# Also protects against logical errors (e.g. a dropped table) that replication
# would copy to the DR region within a second.
# ---------------------------------------------------------------------------
resource "aws_backup_vault" "primary" {
  provider      = aws.primary
  name          = "${local.name}-primary-vault"
  force_destroy = true
}

resource "aws_backup_vault" "dr" {
  provider      = aws.dr
  name          = "${local.name}-dr-vault"
  force_destroy = true
}

# Vault Lock = WORM protection against malicious or accidental deletion.
# Without changeable_for_days this is GOVERNANCE mode. Adding
# changeable_for_days switches to COMPLIANCE mode, which becomes irreversible
# after that grace period.
resource "aws_backup_vault_lock_configuration" "dr" {
  count              = var.enable_vault_lock ? 1 : 0
  provider           = aws.dr
  backup_vault_name  = aws_backup_vault.dr.name
  min_retention_days = var.vault_lock_min_retention_days
  max_retention_days = var.vault_lock_max_retention_days

  lifecycle {
    precondition {
      condition     = var.vault_lock_min_retention_days <= var.dr_copy_retention_days && var.dr_copy_retention_days <= var.vault_lock_max_retention_days
      error_message = "dr_copy_retention_days must lie between vault_lock_min_retention_days and vault_lock_max_retention_days."
    }
  }
}

data "aws_iam_policy_document" "backup_assume" {
  provider = aws.primary

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  provider           = aws.primary
  name               = "${local.name}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  provider   = aws.primary
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  provider   = aws.primary
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_plan" "this" {
  provider = aws.primary
  name     = "${local.name}-daily"

  rule {
    rule_name         = "daily-with-cross-region-copy"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = var.backup_schedule
    start_window      = 60
    completion_window = 360

    lifecycle {
      delete_after = var.backup_retention_days
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn

      lifecycle {
        delete_after = var.dr_copy_retention_days
      }
    }
  }
}

resource "aws_backup_selection" "tagged" {
  provider     = aws.primary
  name         = "${local.name}-tagged"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}

# Alert when a backup or cross-region copy job fails - an unnoticed failing
# backup silently turns a 24 h RPO into weeks.
resource "aws_cloudwatch_event_rule" "backup_failed" {
  provider    = aws.primary
  name        = "${local.name}-backup-failed"
  description = "AWS Backup or copy job failed"

  event_pattern = jsonencode({
    source        = ["aws.backup"]
    "detail-type" = ["Backup Job State Change", "Copy Job State Change"]
    detail = {
      state = ["FAILED", "ABORTED", "EXPIRED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "backup_failed" {
  provider = aws.primary
  rule     = aws_cloudwatch_event_rule.backup_failed.name
  arn      = aws_sns_topic.alerts_primary.arn
}
