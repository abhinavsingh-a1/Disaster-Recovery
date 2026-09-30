# ---------------------------------------------------------------------------
# Database credentials in Secrets Manager, replicated to the DR region so the
# DR web tier can read them even when the primary region is unavailable.
# ---------------------------------------------------------------------------
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  provider    = aws.primary
  name        = "${local.name}/aurora/master"
  description = "Aurora Global Database master credentials"

  # 0 = delete immediately on destroy so the demo can be re-created with the
  # same name. Use 7-30 days in production.
  recovery_window_in_days = 0

  replica {
    region = var.dr_region
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  provider  = aws.primary
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db.result
    dbname   = var.db_name
  })
}
