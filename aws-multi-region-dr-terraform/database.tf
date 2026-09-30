# ---------------------------------------------------------------------------
# Aurora Global Database
#   primary region : read/write cluster
#   DR region      : read-only secondary with storage-level replication
#                    (typically < 1 s lag) - the "always running core" of
#                    pilot light / warm standby / multi-site.
# ---------------------------------------------------------------------------
resource "aws_kms_key" "db_primary" {
  provider                = aws.primary
  description             = "${local.name} Aurora encryption (primary)"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_key" "db_dr" {
  count                   = local.deploy_dr ? 1 : 0
  provider                = aws.dr
  description             = "${local.name} Aurora encryption (DR)"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_rds_global_cluster" "this" {
  provider                  = aws.primary
  global_cluster_identifier = "${local.name}-global"
  engine                    = "aurora-mysql"
  engine_version            = var.db_engine_version
  database_name             = var.db_name
  storage_encrypted         = true
  deletion_protection       = var.db_deletion_protection
}

# ----------------------------- primary region ------------------------------
resource "aws_db_subnet_group" "primary" {
  provider   = aws.primary
  name       = "${local.name}-primary-db"
  subnet_ids = module.network_primary.db_subnet_ids
}

resource "aws_security_group" "db_primary" {
  provider    = aws.primary
  name        = "${local.name}-primary-db"
  description = "Aurora - MySQL from the web tier only"
  vpc_id      = module.network_primary.vpc_id

  ingress {
    description     = "MySQL from web tier"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.app_primary.instance_security_group_id]
  }
}

resource "aws_rds_cluster" "primary" {
  provider                  = aws.primary
  cluster_identifier        = "${local.name}-primary"
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  global_cluster_identifier = aws_rds_global_cluster.this.id
  database_name             = var.db_name
  master_username           = var.db_master_username
  master_password           = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.db_primary.id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.db_primary.arn

  # In-region automated backups: point-in-time restore inside the region
  backup_retention_period = 7
  preferred_backup_window = "01:00-02:00"
  copy_tags_to_snapshot   = true

  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = true

  # Picked up by the AWS Backup selection (backup.tf)
  tags = {
    Backup = "true"
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count                      = var.db_instances_per_region
  provider                   = aws.primary
  identifier                 = "${local.name}-primary-${count.index}"
  cluster_identifier         = aws_rds_cluster.primary.id
  instance_class             = var.db_instance_class
  engine                     = aws_rds_cluster.primary.engine
  engine_version             = aws_rds_cluster.primary.engine_version
  db_subnet_group_name       = aws_db_subnet_group.primary.name
  auto_minor_version_upgrade = true
}

# ------------------------------- DR region ---------------------------------
resource "aws_db_subnet_group" "dr" {
  count      = local.deploy_dr ? 1 : 0
  provider   = aws.dr
  name       = "${local.name}-dr-db"
  subnet_ids = module.network_dr.db_subnet_ids
}

resource "aws_security_group" "db_dr" {
  count       = local.deploy_dr ? 1 : 0
  provider    = aws.dr
  name        = "${local.name}-dr-db"
  description = "Aurora - MySQL from the web tier only"
  vpc_id      = module.network_dr.vpc_id

  ingress {
    description     = "MySQL from web tier"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.app_dr[0].instance_security_group_id]
  }
}

resource "aws_rds_cluster" "dr" {
  count                     = local.deploy_dr ? 1 : 0
  provider                  = aws.dr
  cluster_identifier        = "${local.name}-dr"
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  global_cluster_identifier = aws_rds_global_cluster.this.id

  db_subnet_group_name   = aws_db_subnet_group.dr[0].name
  vpc_security_group_ids = [aws_security_group.db_dr[0].id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.db_dr[0].arn

  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  # multi_site: the DR app can send writes; Aurora forwards them to the writer
  enable_global_write_forwarding = local.active_active

  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = true

  depends_on = [aws_rds_cluster_instance.primary]

  lifecycle {
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "dr" {
  count                      = local.deploy_dr ? var.db_instances_per_region : 0
  provider                   = aws.dr
  identifier                 = "${local.name}-dr-${count.index}"
  cluster_identifier         = aws_rds_cluster.dr[0].id
  instance_class             = var.db_instance_class
  engine                     = aws_rds_cluster.dr[0].engine
  engine_version             = aws_rds_cluster.dr[0].engine_version
  db_subnet_group_name       = aws_db_subnet_group.dr[0].name
  auto_minor_version_upgrade = true
}
