data "aws_region" "primary" {}

locals {
  username = "appadmin"
  db_name  = "appdb"
  db_fqdn  = "db.${var.private_zone_name}"
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

# Credentials secret, replicated to the DR region so recovered apps can read it
# even when the primary Region is down.
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name}/db/credentials"
  description             = "App DB credentials; host is a private DNS name that follows DB failover"
  recovery_window_in_days = 7

  dynamic "replica" {
    for_each = var.same_region ? [] : [var.dr_region]
    content {
      region = replica.value
    }
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    engine   = "postgres"
    host     = local.db_fqdn
    port     = 5432
    dbname   = local.db_name
    username = local.username
    password = random_password.db.result
  })
}

# ---------------- primary ----------------
resource "aws_db_subnet_group" "primary" {
  name       = "${var.name}-primary"
  subnet_ids = var.primary_db_subnet_ids
}

resource "aws_security_group" "primary" {
  name        = "${var.name}-db-primary"
  description = "PostgreSQL primary"
  vpc_id      = var.primary_vpc_id

  ingress {
    description     = "PostgreSQL from app servers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.primary_allowed_sg_ids
  }
}

resource "aws_db_instance" "primary" {
  identifier                          = "${var.name}-primary"
  engine                              = "postgres"
  engine_version                      = var.engine_version
  instance_class                      = var.instance_class
  allocated_storage                   = 20
  max_allocated_storage               = 100
  storage_type                        = "gp3"
  storage_encrypted                   = true
  kms_key_id                          = var.primary_kms_key_arn
  db_name                             = local.db_name
  username                            = local.username
  password                            = random_password.db.result
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  multi_az                            = var.multi_az
  publicly_accessible                 = false
  backup_retention_period             = var.backup_retention_days
  copy_tags_to_snapshot               = true
  auto_minor_version_upgrade          = true
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = !var.deletion_protection
  final_snapshot_identifier           = var.deletion_protection ? "${var.name}-primary-final" : null
  apply_immediately                   = true
  tags                                = { Backup = "true" }
}

# ---------------- DR read replica ----------------
resource "aws_db_subnet_group" "dr" {
  provider   = aws.dr
  name       = "${var.name}-dr"
  subnet_ids = var.dr_db_subnet_ids
}

resource "aws_security_group" "dr" {
  provider    = aws.dr
  name        = "${var.name}-db-dr"
  description = "PostgreSQL DR replica"
  vpc_id      = var.dr_vpc_id

  ingress {
    description     = "PostgreSQL from recovery instances"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.dr_allowed_sg_ids
  }
}

resource "aws_db_instance" "replica" {
  provider                            = aws.dr
  identifier                          = "${var.name}-dr-replica"
  replicate_source_db                 = var.same_region ? aws_db_instance.primary.identifier : aws_db_instance.primary.arn
  instance_class                      = var.instance_class
  storage_type                        = "gp3"
  storage_encrypted                   = true
  kms_key_id                          = var.dr_kms_key_arn
  db_subnet_group_name                = aws_db_subnet_group.dr.name
  vpc_security_group_ids              = [aws_security_group.dr.id]
  multi_az                            = false
  publicly_accessible                 = false
  backup_retention_period             = var.backup_retention_days
  auto_minor_version_upgrade          = true
  iam_database_authentication_enabled = true
  copy_tags_to_snapshot               = true
  skip_final_snapshot                 = true
  apply_immediately                   = true

  # After the FailoverDatabase runbook promotes this replica, Terraform must not
  # try to turn it back into a replica.
  lifecycle {
    ignore_changes = [replicate_source_db]
  }
}

# ---------------- private DNS that follows the failover ----------------
resource "aws_route53_zone" "private" {
  name    = var.private_zone_name
  comment = "Private zone shared by production and DR VPCs"

  vpc {
    vpc_id     = var.primary_vpc_id
    vpc_region = data.aws_region.primary.region
  }

  vpc {
    vpc_id     = var.dr_vpc_id
    vpc_region = var.dr_region
  }
}

resource "aws_route53_record" "db" {
  zone_id = aws_route53_zone.private.zone_id
  name    = local.db_fqdn
  type    = "CNAME"
  ttl     = 30
  records = [aws_db_instance.primary.address]

  # The FailoverDatabase runbook repoints this record to the promoted replica.
  lifecycle {
    ignore_changes = [records]
  }
}
